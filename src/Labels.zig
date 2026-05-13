const std = @import("std");
const c = @cImport({
    @cInclude("stdlib.h");
});

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
    const action = try allocator.dupeZ(u8, action_src);

    var style = Style{};
    if (root.get("style")) |style_value| {
        if (style_value == .object) {
            const obj = style_value.object;
            style.textsize = numberFromValue(obj.get("textsize"), style.textsize);
            style.textpadding = numberFromValue(obj.get("textpadding"), style.textpadding);
            style.rounding = numberFromValue(obj.get("rounding"), style.rounding);
            style.bordersize = numberFromValue(obj.get("bordersize"), style.bordersize);
            style.textfont = try allocator.dupeZ(u8, stringFromValue(obj.get("textfont"), style.textfont));
            if (obj.get("textcolor")) |v| style.textcolor = colorFromValue(v, style.textcolor);
            if (obj.get("bgcolor")) |v| style.bgcolor = colorFromValue(v, style.bgcolor);
            if (obj.get("bordercolor")) |v| style.bordercolor = colorFromValue(v, style.bordercolor);
        }
    } else {
        style.textfont = try allocator.dupeZ(u8, style.textfont);
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
        labels[count] = .{
            .key = try allocator.dupeZ(u8, stringFromValue(obj.get("key"), "")),
            .text = try allocator.dupeZ(u8, stringFromValue(obj.get("text"), "")),
            .address = try allocator.dupeZ(u8, stringFromValue(obj.get("address"), "")),
            .x = numberFromValue(obj.get("x"), 0),
            .y = numberFromValue(obj.get("y"), 0),
            .w = numberFromValue(obj.get("w"), 1),
            .h = numberFromValue(obj.get("h"), 1),
        };
        if (labels[count].key.len > 0 and labels[count].text.len > 0 and labels[count].address.len > 0) {
            count += 1;
        } else {
            std.debug.print("easymotion-render: warning: label[{d}] missing required field (key, text, or address), skipping\n", .{idx});
        }
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
    const command_z = try allocator.dupeZ(u8, command);
    defer allocator.free(command_z);
    if (c.system(command_z.ptr) != 0) return error.ActionFailed;
}
