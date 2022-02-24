const std = @import("std");
const SdlSdk = @import("dep/MasterQ32/SDL.zig/Sdk.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("snake", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();
    exe.addLibraryPath("/usr/lib");

    const sdl_sdk = SdlSdk.init(b);
    // // For some reason this doesn't work on my other computer, so I link it manually, which works.
    // sdl_sdk.link(exe, .dynamic);
    exe.linkLibC();
    exe.linkSystemLibrary("SDL2");
    exe.addPackage(sdl_sdk.getWrapperPackage("MasterQ32/SDL"));

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_tests = b.addTest("src/main.zig");
    exe_tests.setTarget(target);
    exe_tests.setBuildMode(mode);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&exe_tests.step);
}
