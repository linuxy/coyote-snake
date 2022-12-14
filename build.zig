const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const mode = b.standardReleaseOptions();

    const ecsPkg = std.build.Pkg{ .name = "coyote-ecs", .source = std.build.FileSource{ .path = "vendor/coyote-ecs/src/coyote.zig" }};

    const mimalloc = build_mimalloc(b);
    
    const exe = b.addExecutable("snake", "src/coyote-snake.zig");
    exe.setBuildMode(mode);
    exe.linkLibC();
    //Linux paths
    exe.addIncludePath("/usr/include");
    exe.addIncludePath("/usr/include/x86_64-linux-gnu");
    //Homebrew OSX paths
    exe.addIncludePath("/opt/homebrew/Cellar/sdl2/2.24.2/include");
    exe.addLibraryPath("/opt/homebrew/Cellar/sdl2/2.24.2/lib");
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("SDL2_image");
    exe.addLibraryPath("vendor/coyote-ecs/vendor/mimalloc");
    exe.linkSystemLibrary("mimalloc");
    exe.addPackage(ecsPkg);
    //exe.use_stage1 = true;
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const make_step = b.step("mimalloc", "Make mimalloc library");
    make_step.dependOn(&mimalloc.step);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

fn build_mimalloc(b: *std.build.Builder) *std.build.RunStep {

    const cmake = b.addSystemCommand(
        &[_][]const u8{
            "cmake",
            "-S./vendor/coyote-ecs/vendor/mimalloc/",
            "-B./vendor/coyote-ecs/vendor/mimalloc/",
        },
    );
    const make = b.addSystemCommand(
        &[_][]const u8{
            "make",
            "-j4",
            "-C./vendor/coyote-ecs/vendor/mimalloc",
        },
    );

    make.step.dependOn(&cmake.step);
    return make;
}