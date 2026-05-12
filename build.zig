const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const protocol_dir = b.path(".zig-cache/protocol");
    const mkdir = b.addSystemCommand(&.{ "mkdir", "-p", ".zig-cache/protocol" });

    const layer_xml = "protocol/wlr-layer-shell-unstable-v1.xml";
    const gen_header = b.addSystemCommand(&.{
        "wayland-scanner",
        "client-header",
        layer_xml,
        ".zig-cache/protocol/wlr-layer-shell-unstable-v1-client-protocol.h",
    });
    gen_header.step.dependOn(&mkdir.step);

    const gen_code = b.addSystemCommand(&.{
        "wayland-scanner",
        "private-code",
        layer_xml,
        ".zig-cache/protocol/wlr-layer-shell-unstable-v1-protocol.c",
    });
    gen_code.step.dependOn(&mkdir.step);

    const exe = b.addExecutable(.{
        .name = "easymotion-render",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    exe.step.dependOn(&gen_header.step);
    exe.step.dependOn(&gen_code.step);
    exe.root_module.addIncludePath(protocol_dir);
    exe.root_module.addIncludePath(b.path("src/c"));
    exe.root_module.addCSourceFile(.{ .file = b.path(".zig-cache/protocol/wlr-layer-shell-unstable-v1-protocol.c") });
    exe.root_module.addCSourceFile(.{ .file = b.path("src/c/shim.c") });
    exe.root_module.link_libc = true;
    exe.root_module.linkSystemLibrary("wayland-client", .{});
    exe.root_module.linkSystemLibrary("cairo", .{});
    exe.root_module.linkSystemLibrary("pangocairo-1.0", .{});
    exe.root_module.linkSystemLibrary("pango-1.0", .{});
    exe.root_module.linkSystemLibrary("gobject-2.0", .{});
    exe.root_module.linkSystemLibrary("glib-2.0", .{});
    exe.root_module.linkSystemLibrary("xkbcommon", .{});

    b.installArtifact(exe);
}
