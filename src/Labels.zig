const std = @import("std");
const c = @import("c");

pub const Color = [4]f64;

pub const Style = struct {
    textsize: f64 = 128,
    textcolor: Color = .{ 0.98, 0.85, 0.18, 1.0 },
    bgcolor: Color = .{ 0.23, 0.22, 0.20, 0.80 },
    textfont: []const u8 = "JetBrains Mono",
    textpadding: f64 = 8,
    rounding: f64 = 6,
    bordersize: f64 = 2,
    bordercolor: Color = .{ 0.40, 0.36, 0.33, 1.0 },
};

pub const Label = struct {
    key: []const u8,
    text: []const u8,
    address: []const u8,
    x: f64,
    y: f64,
    w: f64,
    h: f64,
};

pub const Config = struct {
    action: []const u8,
    labels: []Label,
    style: Style,
};

fn colorFromValue(value: std.json.Value, default: Color) Color {
    const array = switch (value) {
        .array => |a| a,
        else => return default,
    };
    if (array.items.len < 4) return default;
    var out = default;
    for (0..4) |i| {
        out[i] = switch (array.items[i]) {
            .float => |v| v,
            .integer => |v| @floatFromInt(v),
            else => default[i],
        };
    }
    return out;
}

fn numberFromValue(value: ?std.json.Value, default: f64) f64 {
    if (value == null) return default;
    return switch (value.?) {
        .float => |v| v,
        .integer => |v| @floatFromInt(v),
        else => default,
    };
}

fn finiteOr(value: f64, default: f64) f64 {
    return if (std.math.isFinite(value)) value else default;
}

fn clampNumber(value: ?std.json.Value, default: f64, min: f64, max: f64) f64 {
    return std.math.clamp(finiteOr(numberFromValue(value, default), default), min, max);
}

fn stringFromValue(value: ?std.json.Value, default: []const u8) []const u8 {
    if (value == null) return default;
    return switch (value.?) {
        .string => |v| v,
        else => default,
    };
}

pub fn parseConfig(allocator: std.mem.Allocator, bytes: []const u8) !Config {
    var tree = try std.json.parseFromSlice(std.json.Value, allocator, bytes, .{});
    defer tree.deinit();

    const root = switch (tree.value) {
        .object => |o| o,
        else => return error.InvalidJsonRoot,
    };

    const action_src = stringFromValue(root.get("action"), "hyprctl eval 'hl.dispatch(hl.dsp.focus({window = \"address:{}\"}))'");
    const action = try allocator.dupeSentinel(u8, action_src, 0);

    var style = Style{};
    if (root.get("style")) |style_value| {
        if (style_value == .object) {
            const obj = style_value.object;
            style.textsize = clampNumber(obj.get("textsize"), style.textsize, 1, 4096);
            style.textpadding = clampNumber(obj.get("textpadding"), style.textpadding, 0, 1024);
            style.rounding = clampNumber(obj.get("rounding"), style.rounding, 0, 1024);
            style.bordersize = clampNumber(obj.get("bordersize"), style.bordersize, 0, 1024);
            style.textfont = try allocator.dupeSentinel(u8, stringFromValue(obj.get("textfont"), style.textfont), 0);
            if (obj.get("textcolor")) |v| style.textcolor = colorFromValue(v, style.textcolor);
            if (obj.get("bgcolor")) |v| style.bgcolor = colorFromValue(v, style.bgcolor);
            if (obj.get("bordercolor")) |v| style.bordercolor = colorFromValue(v, style.bordercolor);
        }
    } else {
        style.textfont = try allocator.dupeSentinel(u8, style.textfont, 0);
    }

    const label_value = root.get("labels") orelse return error.MissingLabels;
    const array = switch (label_value) {
        .array => |a| a,
        else => return error.InvalidLabels,
    };

    var labels = try allocator.alloc(Label, array.items.len);
    var count: usize = 0;
    for (array.items, 0..) |item, idx| {
        if (item != .object) {
            std.debug.print("easymotion-render: warning: label[{d}] is not an object, skipping\n", .{idx});
            continue;
        }
        const obj = item.object;
        const key_src = stringFromValue(obj.get("key"), "");
        const text_src = stringFromValue(obj.get("text"), "");
        const address_src = stringFromValue(obj.get("address"), "");
        if (key_src.len == 0 or text_src.len == 0 or address_src.len == 0) {
            std.debug.print("easymotion-render: warning: label[{d}] missing required field (key, text, or address), skipping\n", .{idx});
            continue;
        }
        labels[count] = .{
            .key = try allocator.dupeSentinel(u8, key_src, 0),
            .text = try allocator.dupeSentinel(u8, text_src, 0),
            .address = try allocator.dupeSentinel(u8, address_src, 0),
            .x = finiteOr(numberFromValue(obj.get("x"), 0), 0),
            .y = finiteOr(numberFromValue(obj.get("y"), 0), 0),
            .w = finiteOr(numberFromValue(obj.get("w"), 1), 1),
            .h = finiteOr(numberFromValue(obj.get("h"), 1), 1),
        };
        count += 1;
    }

    return .{ .action = action, .labels = labels[0..count], .style = style };
}

fn isSafeActionValue(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |ch| {
        const safe = std.ascii.isAlphanumeric(ch) or ch == ':' or ch == '-' or ch == '_' or ch == '.';
        if (!safe) return false;
    }
    return true;
}

pub fn runAction(allocator: std.mem.Allocator, action_template: []const u8, address: []const u8) !void {
    if (std.mem.indexOf(u8, action_template, "{}") != null and !isSafeActionValue(address)) return error.InvalidActionValue;
    const command = try std.mem.replaceOwned(u8, allocator, action_template, "{}", address);
    defer allocator.free(command);
    const command_z = try allocator.dupeSentinel(u8, command, 0);
    defer allocator.free(command_z);
    if (c.system(command_z.ptr) != 0) return error.ActionFailed;
}
