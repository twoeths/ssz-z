const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addStaticLibrary(.{
        .name = "ssz-z",
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const util_module = b.createModule(.{
        .root_source_file = b.path("lib/hex.zig"),
        .target = target,
        .optimize = optimize,
    });
    const hash_module = b.createModule(.{
        .root_source_file = b.path("src/hash/merkleize.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib.root_module.addImport("util", util_module);
    lib.root_module.addImport("hash", hash_module);

    // This declares intent for the library to be installed into the standard
    // location when the user invokes the "install" step (the default step when
    // running `zig build`).
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "ssz-z",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).
    b.installArtifact(exe);

    exe.root_module.addImport("util", util_module);
    exe.root_module.addImport("hash", hash_module);

    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Creates a step for unit testing. This only builds the test executable
    // but does not run it.
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib_unit_tests.root_module.addImport("util", util_module);
    lib_unit_tests.root_module.addImport("hash", hash_module);

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Similar to the run step above, this creates a test step in test folder
    const run_lib_unit_valid_tests = addValidTest(b, target, optimize, util_module, hash_module);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_unit_tests.root_module.addImport("util", util_module);
    exe_unit_tests.root_module.addImport("hash", hash_module);

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    // TODO: cannot display information in "zig build test" https://github.com/ziglang/zig/issues/16673
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_lib_unit_valid_tests.step);
}

fn addValidTest(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, util_module: *std.Build.Module, hash_module: *std.Build.Module) *std.Build.Step.Run {
    // Similar to the run step above, this creates a test step in test folder
    const lib_unit_valid_tests = b.addTest(.{
        .root_source_file = b.path("test/unit/root.zig"),
        // use this to run a specific test
        // .root_source_file = b.path("test/unit/type/vector_composite.zig"),
        .target = target,
        .optimize = optimize,
    });

    lib_unit_valid_tests.root_module.addImport("util", util_module);
    lib_unit_valid_tests.root_module.addImport("hash", hash_module);

    const ssz_module = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    ssz_module.addImport("util", util_module);
    ssz_module.addImport("hash", hash_module);
    lib_unit_valid_tests.root_module.addImport("ssz", ssz_module);

    const run_lib_unit_valid_tests = b.addRunArtifact(lib_unit_valid_tests);
    return run_lib_unit_valid_tests;
}
