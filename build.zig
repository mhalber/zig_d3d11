const std = @import("std");
const Builder = std.build.Builder;

pub fn build(b: *Builder) void {
    const mode = b.standardReleaseOptions();
    const exe = b.addExecutable("d3d11_traingle", "src/d3d11_triangle.zig");

    exe.addPackagePath("win32", "../zig-win32/win32.zig");
    exe.addPackagePath("msh_math", "../msh_math/src/vec_math.zig");
    exe.setTarget(.{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu });
    exe.setBuildMode(mode);
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
