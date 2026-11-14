const std = @import("std");
const Labels = @import("Labels.zig");
const Layer = @import("Layer.zig");

fn usage() void {
    std.debug.print("usage: easymotion-render <config.json>\n", .{});
}

/// The payload is written by the Lua frontend under a known name and unlinked
/// once consumed; anything else is refused rather than deleted.
fn isPayloadPath(path: []const u8) bool {
    const base = std.fs.path.basename(path);
    return std.mem.startsWith(u8, base, "easymotion-") and std.mem.endsWith(u8, base, ".json");
}

pub fn main(init: std.process.Init) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.Args.toSlice(init.minimal.args, allocator);
    if (args.len != 2) {
        usage();
        std.process.exit(2);
    }

    const path = args[1];
    if (!isPayloadPath(path)) {
        std.debug.print("easymotion-render: refusing to consume {s}: not an easymotion payload\n", .{path});
        std.process.exit(2);
    }

    const bytes = std.Io.Dir.readFileAlloc(.cwd(), init.io, path, allocator, .limited(10 * 1024 * 1024)) catch |err| {
        std.debug.print("easymotion-render: failed to read {s}: {s}\n", .{ path, @errorName(err) });
        std.process.exit(2);
    };

    const config = Labels.parseConfig(allocator, bytes) catch |err| {
        std.debug.print("easymotion-render: invalid JSON config: {s}\n", .{@errorName(err)});
        std.process.exit(2);
    };
    std.Io.Dir.deleteFile(.cwd(), init.io, path) catch {};

    if (config.labels.len == 0) {
        std.debug.print("easymotion-render: no labels to render\n", .{});
        std.process.exit(2);
    }

    var app = Layer.App{ .allocator = allocator, .config = config };
    app.run() catch |err| {
        std.debug.print("easymotion-render: {s}\n", .{@errorName(err)});
        app.deinit();
        std.process.exit(1);
    };
    app.deinit();
}
