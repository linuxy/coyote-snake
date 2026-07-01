const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const coyote_mod = b.createModule(.{
        .root_source_file = b.path("../coyote-ecs/src/coyote.zig"),
        .target = target,
        .optimize = optimize,
    });

    const sdl_mod = b.createModule(.{
        .root_source_file = b.path("src/sdl.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/coyote-snake.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "coyote-ecs", .module = coyote_mod },
            .{ .name = "sdl", .module = sdl_mod },
        },
    });

    const exe = b.addExecutable(.{
        .name = "snake",
        .root_module = exe_mod,
    });

    switch (target.result.os.tag) {
        .macos => {
            exe.root_module.addIncludePath(b.graph.cwdRelativePath("/opt/homebrew/Cellar/sdl2/2.24.2/include"));
            exe.root_module.addLibraryPath(b.graph.cwdRelativePath("/opt/homebrew/Cellar/sdl2/2.24.2/lib"));
        },
        else => {},
    }

    exe.root_module.linkSystemLibrary("SDL2", .{});
    exe.root_module.linkSystemLibrary("SDL2_image", .{});

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
