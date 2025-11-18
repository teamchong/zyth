const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main pyaot compiler executable
    const exe = b.addExecutable(.{
        .name = "pyaot",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);

    // Run command
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the pyaot compiler");
    run_step.dependOn(&run_cmd.step);

    // Zig runtime tests
    // Create shared ast module
    const ast_module = b.createModule(.{
        .root_source_file = b.path("src/ast.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Create comptime_eval module with ast dependency
    const comptime_eval_module = b.createModule(.{
        .root_source_file = b.path("src/analysis/comptime_eval.zig"),
        .target = target,
        .optimize = optimize,
    });
    comptime_eval_module.addImport("ast", ast_module);

    // Create test module
    const runtime_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/test_comptime_eval.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add imports to test module
    runtime_tests.root_module.addImport("ast", ast_module);
    runtime_tests.root_module.addImport("comptime_eval", comptime_eval_module);

    const run_runtime_tests = b.addRunArtifact(runtime_tests);
    const test_step = b.step("test-zig", "Run Zig runtime unit tests");
    test_step.dependOn(&run_runtime_tests.step);
}
