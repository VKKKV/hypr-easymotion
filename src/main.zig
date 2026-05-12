const std = @import("std");
const Labels = @import("Labels.zig");
const Layer = @import("Layer.zig");

fn usage() void {
    std.debug.print("usage: easymotion-render <config.json>\n", .{});
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

    const bytes = std.Io.Dir.readFileAlloc(.cwd(), init.io, args[1], allocator, .limited(10 * 1024 * 1024)) catch |err| {
        std.debug.print("easymotion-render: failed to read {s}: {s}\n", .{ args[1], @errorName(err) });
        std.process.exit(2);
    };
    defer allocator.free(bytes);
    std.Io.Dir.deleteFile(.cwd(), init.io, args[1]) catch {};

    const config = Labels.parseConfig(allocator, bytes) catch |err| {
        std.debug.print("easymotion-render: invalid JSON config: {s}\n", .{@errorName(err)});
        std.process.exit(2);
    };
    if (config.labels.len == 0) {
        std.debug.print("easymotion-render: no labels to render\n", .{});
        std.process.exit(2);
    }

    var app = Layer.App{ .allocator = allocator, .config = config };
    defer app.deinit();
    app.run() catch |err| {
        std.debug.print("easymotion-render: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}
