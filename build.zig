const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .root_source_file = .{ .path = "src/coyote-snake.zig"},
        .optimize = optimize,
        .target = target,
        .name = "snake",
    });

    exe.linkLibC();

    exe.addAnonymousModule("coyote-ecs", .{ 
        .source_file = .{ .path = "./vendor/coyote-ecs/src/coyote.zig" },
    });

    //Linux paths
    exe.addIncludePath("/usr/include");
    exe.addIncludePath("/usr/include/x86_64-linux-gnu");
    //Homebrew OSX paths
    exe.addIncludePath("/opt/homebrew/Cellar/sdl2/2.24.2/include");
    exe.addLibraryPath("/opt/homebrew/Cellar/sdl2/2.24.2/lib");
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("SDL2_image");
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}