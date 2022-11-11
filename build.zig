const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const ecsPkg = std.build.Pkg{ .name = "coyote-ecs", .source = std.build.FileSource{ .path = "vendor/coyote-ecs/src/coyote.zig" }};

    const exe = b.addExecutable("snake", "src/snake.zig");
    exe.setBuildMode(mode);
    exe.linkLibC();
    exe.addIncludePath("/usr/include");
    exe.addIncludePath("/usr/include/x86_64-linux-gnu");
    exe.linkSystemLibrary("SDL2");
    exe.addPackage(ecsPkg);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}