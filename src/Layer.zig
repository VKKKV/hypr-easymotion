const std = @import("std");
const Labels = @import("Labels.zig");

const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("sys/mman.h");
    @cInclude("wayland-client.h");
    @cInclude("xkbcommon/xkbcommon.h");
    @cInclude("shim.h");
});

const KEY_ESC: u32 = 0xff1b;
const KEY_RELEASED: u32 = 0;
const KEY_PRESSED: u32 = 1;
const MAX_OUTPUTS: usize = 16;

const Output = struct {
    app: ?*App = null,
    wl: ?*c.wl_output = null,
    surface: ?*c.wl_surface = null,
    layer_surface: ?*c.struct_zwlr_layer_surface_v1 = null,
    buffer: ?*c.wl_buffer = null,
    shm_pool: ?*c.wl_shm_pool = null,
    shm_fd: c_int = -1,
    shm_data: ?[*]u8 = null,
    shm_size: usize = 0,
    x: i32 = 0,
    y: i32 = 0,
    width: i32 = 1,
    height: i32 = 1,
    rendered_x: i32 = 0,
    rendered_y: i32 = 0,
    rendered_width: i32 = 0,
    rendered_height: i32 = 0,
    rendered: bool = false,
};

pub const App = struct {
    allocator: std.mem.Allocator,
    config: Labels.Config,
    display: ?*c.wl_display = null,
    registry: ?*c.wl_registry = null,
    compositor: ?*c.wl_compositor = null,
    shm: ?*c.wl_shm = null,
    seat: ?*c.wl_seat = null,
    layer_shell: ?*c.struct_zwlr_layer_shell_v1 = null,
    keyboard: ?*c.wl_keyboard = null,
    xkb_context: ?*c.xkb_context = null,
    xkb_keymap: ?*c.xkb_keymap = null,
    xkb_state: ?*c.xkb_state = null,
    running: bool = true,
    action_failed: bool = false,
    pending_address: ?[]const u8 = null,
    outputs: [MAX_OUTPUTS]Output = [_]Output{.{}} ** MAX_OUTPUTS,
    output_count: usize = 0,

    pub fn run(self: *App) !void {
        self.display = c.wl_display_connect(null) orelse return error.WaylandConnectFailed;
        self.registry = c.wl_display_get_registry(self.display) orelse return error.RegistryFailed;
        _ = c.wl_registry_add_listener(self.registry, &registry_listener, self);
        if (c.wl_display_roundtrip(self.display) < 0) return error.RegistryRoundtripFailed;
        if (c.wl_display_roundtrip(self.display) < 0) return error.OutputRoundtripFailed;
        if (self.compositor == null) return error.MissingWlCompositor;
        if (self.shm == null) return error.MissingWlShm;
        if (self.layer_shell == null) return error.MissingLayerShell;
        if (self.seat == null) return error.MissingSeat;
        if (self.output_count == 0) return error.MissingOutput;

        for (self.outputs[0..self.output_count]) |*output| {
            output.app = self;
            output.surface = c.em_compositor_create_surface(self.compositor) orelse return error.SurfaceCreateFailed;
            output.layer_surface = c.em_layer_shell_get_layer_surface(self.layer_shell, output.surface, output.wl) orelse return error.LayerSurfaceCreateFailed;
            c.em_layer_surface_set_fullscreen(output.layer_surface);
            _ = c.zwlr_layer_surface_v1_add_listener(output.layer_surface, &layer_listener, output);
            c.wl_surface_commit(output.surface);
        }

        self.keyboard = c.em_seat_get_keyboard(self.seat) orelse return error.KeyboardFailed;
        _ = c.wl_keyboard_add_listener(self.keyboard, &keyboard_listener, self);

        while (self.running and c.wl_display_dispatch(self.display) >= 0) {}
        if (self.pending_address) |address| {
            self.releaseOverlay() catch |err| {
                std.debug.print("easymotion-render: overlay teardown failed: {s}\n", .{@errorName(err)});
                self.action_failed = true;
                return;
            };
            Labels.runAction(self.allocator, self.config.action, address) catch |err| {
                std.debug.print("easymotion-render: action failed: {s}\n", .{@errorName(err)});
                self.action_failed = true;
            };
        }
        if (self.action_failed) return error.ActionFailed;
    }

    fn releaseOverlay(self: *App) !void {
        if (self.keyboard) |keyboard| {
            c.wl_keyboard_destroy(keyboard);
            self.keyboard = null;
        }

        for (self.outputs[0..self.output_count]) |*output| {
            self.resetOutputBuffer(output);
            if (output.layer_surface) |layer_surface| {
                c.zwlr_layer_surface_v1_destroy(layer_surface);
                output.layer_surface = null;
            }
            if (output.surface) |surface| {
                c.wl_surface_destroy(surface);
                output.surface = null;
            }
        }

        if (self.display) |display| {
            if (c.wl_display_flush(display) < 0) return error.DisplayFlushFailed;
            // Ensure the compositor processes our keyboard/surface teardown before
            // the external focus action runs. Unlike the upstream in-process
            // plugin, this renderer is a separate Wayland client that may still
            // own exclusive keyboard focus until the destroy requests are
            // acknowledged server-side.
            if (c.wl_display_roundtrip(display) < 0) return error.DisplayRoundtripFailed;
        }
    }

    fn resetOutputBuffer(_: *App, output: *Output) void {
        if (output.shm_data) |data| _ = c.munmap(data, output.shm_size);
        if (output.shm_fd >= 0) _ = c.close(output.shm_fd);
        if (output.buffer) |p| c.wl_buffer_destroy(p);
        if (output.shm_pool) |p| c.wl_shm_pool_destroy(p);
        output.buffer = null;
        output.shm_pool = null;
        output.shm_fd = -1;
        output.shm_data = null;
        output.shm_size = 0;
    }

    fn tryRenderOutput(self: *App, output: *Output) !void {
        if (output.surface == null or output.layer_surface == null) return;
        if (output.width <= 1 or output.height <= 1) return;
        if (output.rendered and output.rendered_x == output.x and output.rendered_y == output.y and output.rendered_width == output.width and output.rendered_height == output.height) return;

        const stride: i32 = output.width * 4;
        const size: i32 = stride * output.height;
        if (output.buffer == null or output.rendered_width != output.width or output.rendered_height != output.height) {
            self.resetOutputBuffer(output);
            output.shm_fd = c.em_create_shm_file(size);
            if (output.shm_fd < 0) return error.ShmFileFailed;
            output.shm_size = @intCast(size);
            const mapped = c.mmap(null, output.shm_size, c.PROT_READ | c.PROT_WRITE, c.MAP_SHARED, output.shm_fd, 0);
            if (mapped == c.MAP_FAILED) return error.MmapFailed;
            output.shm_data = @ptrCast(mapped);
            output.shm_pool = c.em_shm_create_pool(self.shm, output.shm_fd, size) orelse return error.ShmPoolFailed;
            output.buffer = c.em_shm_pool_create_argb8888_buffer(output.shm_pool, output.width, output.height, stride) orelse return error.BufferFailed;
        }

        var c_style = c.em_style{
            .textsize = self.config.style.textsize,
            .textcolor = self.config.style.textcolor,
            .bgcolor = self.config.style.bgcolor,
            .textfont = self.config.style.textfont.ptr,
            .textpadding = self.config.style.textpadding,
            .rounding = self.config.style.rounding,
            .bordersize = self.config.style.bordersize,
            .bordercolor = self.config.style.bordercolor,
        };
        var c_labels = try self.allocator.alloc(c.em_label, self.config.labels.len);
        defer self.allocator.free(c_labels);
        for (self.config.labels, 0..) |label, i| {
            c_labels[i] = .{ .text = label.text.ptr, .x = label.x - @as(f64, @floatFromInt(output.x)), .y = label.y - @as(f64, @floatFromInt(output.y)), .w = label.w, .h = label.h };
        }
        if (c.em_render_labels(output.shm_data.?, output.width, output.height, stride, &c_style, c_labels.ptr, @intCast(c_labels.len)) != 0) return error.RenderFailed;
        c.em_surface_attach_damage_commit(output.surface, output.buffer, output.width, output.height);
        output.rendered_x = output.x;
        output.rendered_y = output.y;
        output.rendered_width = output.width;
        output.rendered_height = output.height;
        output.rendered = true;
    }

    fn handleKey(self: *App, state: u32, key: u32) void {
        if (state != KEY_PRESSED or self.xkb_state == null) return;
        const keysym = c.xkb_state_key_get_one_sym(self.xkb_state, key + 8);
        if (keysym == KEY_ESC) {
            self.running = false;
            return;
        }
        var buf: [64]u8 = undefined;
        const len = c.xkb_keysym_to_utf8(keysym, &buf, buf.len);
        if (len <= 0) return;
        const typed = buf[0..@as(usize, @intCast(len - 1))];
        for (self.config.labels) |label| {
            if (std.mem.eql(u8, typed, label.key)) {
                self.pending_address = label.address;
                self.running = false;
                return;
            }
        }
    }

    pub fn deinit(self: *App) void {
        for (self.outputs[0..self.output_count]) |*output| {
            if (output.shm_data) |data| _ = c.munmap(data, output.shm_size);
            if (output.shm_fd >= 0) _ = c.close(output.shm_fd);
            if (output.buffer) |p| c.wl_buffer_destroy(p);
            if (output.shm_pool) |p| c.wl_shm_pool_destroy(p);
            if (output.layer_surface) |p| c.zwlr_layer_surface_v1_destroy(p);
            if (output.surface) |p| c.wl_surface_destroy(p);
            if (output.wl) |p| c.wl_output_destroy(p);
        }
        if (self.xkb_state) |p| c.xkb_state_unref(p);
        if (self.xkb_keymap) |p| c.xkb_keymap_unref(p);
        if (self.xkb_context) |p| c.xkb_context_unref(p);
        if (self.keyboard) |p| c.wl_keyboard_destroy(p);
        if (self.display) |p| c.wl_display_disconnect(p);
    }
};

fn registryGlobal(data: ?*anyopaque, registry: ?*c.wl_registry, name: u32, interface: [*c]const u8, version: u32) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    const iface = std.mem.span(interface);
    if (std.mem.eql(u8, iface, "wl_compositor")) app.compositor = c.em_bind_compositor(registry, name, version) else if (std.mem.eql(u8, iface, "wl_shm")) app.shm = c.em_bind_shm(registry, name, version) else if (std.mem.eql(u8, iface, "wl_seat")) app.seat = c.em_bind_seat(registry, name, version) else if (std.mem.eql(u8, iface, "wl_output")) {
        if (app.output_count < MAX_OUTPUTS) {
            const output = &app.outputs[app.output_count];
            output.* = .{ .wl = c.em_bind_output(registry, name, version) };
            _ = c.wl_output_add_listener(output.wl, &output_listener, output);
            app.output_count += 1;
        }
    } else if (std.mem.eql(u8, iface, "zwlr_layer_shell_v1")) app.layer_shell = c.em_bind_layer_shell(registry, name, version);
}

fn registryRemove(_: ?*anyopaque, _: ?*c.wl_registry, _: u32) callconv(.c) void {}

const registry_listener = c.wl_registry_listener{ .global = registryGlobal, .global_remove = registryRemove };

fn outputGeometry(data: ?*anyopaque, _: ?*c.wl_output, x: i32, y: i32, _: i32, _: i32, _: i32, _: [*c]const u8, _: [*c]const u8, _: i32) callconv(.c) void {
    const output: *Output = @ptrCast(@alignCast(data.?));
    output.x = x;
    output.y = y;
    if (output.app) |app| {
        app.tryRenderOutput(output) catch |err| {
            std.debug.print("easymotion-render: render failed: {s}\n", .{@errorName(err)});
            app.running = false;
        };
    }
}

fn outputMode(data: ?*anyopaque, _: ?*c.wl_output, flags: u32, width: i32, height: i32, _: i32) callconv(.c) void {
    if ((flags & c.WL_OUTPUT_MODE_CURRENT) == 0) return;
    const output: *Output = @ptrCast(@alignCast(data.?));
    output.width = width;
    output.height = height;
    if (output.app) |app| {
        app.tryRenderOutput(output) catch |err| {
            std.debug.print("easymotion-render: render failed: {s}\n", .{@errorName(err)});
            app.running = false;
        };
    }
}

fn outputDone(_: ?*anyopaque, _: ?*c.wl_output) callconv(.c) void {}
fn outputScale(_: ?*anyopaque, _: ?*c.wl_output, _: i32) callconv(.c) void {}
fn outputName(_: ?*anyopaque, _: ?*c.wl_output, _: [*c]const u8) callconv(.c) void {}
fn outputDescription(_: ?*anyopaque, _: ?*c.wl_output, _: [*c]const u8) callconv(.c) void {}

const output_listener = c.wl_output_listener{
    .geometry = outputGeometry,
    .mode = outputMode,
    .done = outputDone,
    .scale = outputScale,
    .name = outputName,
    .description = outputDescription,
};

fn layerConfigure(data: ?*anyopaque, surface: ?*c.struct_zwlr_layer_surface_v1, serial: u32, width: u32, height: u32) callconv(.c) void {
    const output: *Output = @ptrCast(@alignCast(data.?));
    output.width = if (width == 0) output.width else @intCast(width);
    output.height = if (height == 0) output.height else @intCast(height);
    c.em_layer_surface_ack_configure(surface, serial);
    const app = output.app.?;
    app.tryRenderOutput(output) catch |err| {
        std.debug.print("easymotion-render: render failed: {s}\n", .{@errorName(err)});
        app.running = false;
    };
}

fn layerClosed(data: ?*anyopaque, _: ?*c.struct_zwlr_layer_surface_v1) callconv(.c) void {
    const output: *Output = @ptrCast(@alignCast(data.?));
    const app = output.app.?;
    app.running = false;
}

const layer_listener = c.zwlr_layer_surface_v1_listener{ .configure = layerConfigure, .closed = layerClosed };

fn keyboardKeymap(data: ?*anyopaque, _: ?*c.wl_keyboard, format: u32, fd: i32, size: u32) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    defer _ = c.close(fd);
    if (format != c.WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) return;
    const mapped = c.mmap(null, size, c.PROT_READ, c.MAP_PRIVATE, fd, 0);
    if (mapped == c.MAP_FAILED) return;
    defer _ = c.munmap(mapped, size);

    app.xkb_context = c.xkb_context_new(c.XKB_CONTEXT_NO_FLAGS);
    app.xkb_keymap = c.xkb_keymap_new_from_string(app.xkb_context, @ptrCast(mapped), c.XKB_KEYMAP_FORMAT_TEXT_V1, c.XKB_KEYMAP_COMPILE_NO_FLAGS);
    app.xkb_state = c.xkb_state_new(app.xkb_keymap);
}

fn keyboardEnter(_: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, _: ?*c.wl_surface, _: ?*c.wl_array) callconv(.c) void {}
fn keyboardLeave(_: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, _: ?*c.wl_surface) callconv(.c) void {}
fn keyboardKey(data: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, _: u32, key: u32, state: u32) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    app.handleKey(state, key);
}
fn keyboardModifiers(data: ?*anyopaque, _: ?*c.wl_keyboard, _: u32, depressed: u32, latched: u32, locked: u32, group: u32) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(data.?));
    if (app.xkb_state) |state| _ = c.xkb_state_update_mask(state, depressed, latched, locked, 0, 0, group);
}
fn keyboardRepeat(_: ?*anyopaque, _: ?*c.wl_keyboard, _: i32, _: i32) callconv(.c) void {}

const keyboard_listener = c.wl_keyboard_listener{
    .keymap = keyboardKeymap,
    .enter = keyboardEnter,
    .leave = keyboardLeave,
    .key = keyboardKey,
    .modifiers = keyboardModifiers,
    .repeat_info = keyboardRepeat,
};
