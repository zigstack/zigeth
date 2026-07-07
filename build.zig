const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Build options
    const enable_benchmarks = b.option(bool, "benchmarks", "Build benchmarks") orelse false;
    const enable_examples = b.option(bool, "examples", "Build examples") orelse false;

    // Get zig-eth-secp256k1 dependency
    const secp256k1_dep = b.dependency("zig_eth_secp256k1", .{
        .target = target,
        .optimize = optimize,
    });
    const secp256k1_mod = secp256k1_dep.module("zig-eth-secp256k1");
    const secp256k1_artifact = secp256k1_dep.artifact("secp256k1");

    // Create the main library module.
    //
    // Zig 0.16 moved `linkLibC` off the Compile step and onto the Module, so
    // we set `link_libc = true` at module creation time rather than the old
    // `lib.linkLibC()` call site.
    const zigeth_mod = b.addModule("zigeth", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    zigeth_mod.addImport("secp256k1", secp256k1_mod);

    // Build static library
    const lib = b.addLibrary(.{
        .name = "zigeth",
        .root_module = zigeth_mod,
    });
    lib.root_module.linkLibrary(secp256k1_artifact);
    b.installArtifact(lib);

    // Build executable (CLI tool) — DISABLED during Zig 0.16 migration.
    // The CLI uses many 0.15 stdlib idioms (argsAlloc, stdout writer API,
    // etc.). Library is the primary deliverable; re-enable once the CLI
    // is ported to the 0.16 Io.Writer + process API.
    //
    // const exe_mod = b.createModule(.{ ... });
    // const exe = b.addExecutable(.{ ... });
    // b.installArtifact(exe);
    // const run_step = b.step("run", "Run the zigeth CLI");

    // Unit tests for library
    const lib_test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .ReleaseSafe,
        .link_libc = true,
    });
    lib_test_mod.addImport("secp256k1", secp256k1_mod);
    const lib_unit_tests = b.addTest(.{
        .root_module = lib_test_mod,
    });
    lib_unit_tests.root_module.linkLibrary(secp256k1_artifact);
    lib_unit_tests.bundle_ubsan_rt = true;
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    // Unit tests for executable — disabled during 0.16 migration.

    const test_step = b.step("test", "Run all unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    // Documentation generation
    const doc_step = b.step("docs", "Generate documentation");
    const install_docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    doc_step.dependOn(&install_docs.step);

    if (enable_benchmarks) {
        const bench_step = b.step("bench", "Run benchmarks");
        _ = bench_step;
    }

    if (enable_examples) {
        const examples_step = b.step("examples", "Build all examples");
        const example_names = [_][]const u8{
            "01_wallet_creation",
            "02_query_blockchain",
            "03_send_transaction",
            "04_smart_contracts",
            "05_transaction_receipts",
            "06_event_monitoring",
            "07_complete_workflow",
            "08_account_abstraction",
            "09_etherspot_userop",
            "10_error_handling",
        };
        for (example_names) |example_name| {
            const example_path = b.fmt("examples/{s}.zig", .{example_name});
            const example_mod = b.createModule(.{
                .root_source_file = b.path(example_path),
                .target = target,
                .optimize = optimize,
                .link_libc = true,
            });
            example_mod.addImport("zigeth", zigeth_mod);
            const example_exe = b.addExecutable(.{
                .name = example_name,
                .root_module = example_mod,
            });
            example_exe.root_module.linkLibrary(secp256k1_artifact);
            const install_example = b.addInstallArtifact(example_exe, .{
                .dest_dir = .{ .override = .{ .custom = "examples" } },
            });
            examples_step.dependOn(&install_example.step);
            const run_example = b.addRunArtifact(example_exe);
            const run_example_step = b.step(
                b.fmt("run-{s}", .{example_name}),
                b.fmt("Run the {s} example", .{example_name}),
            );
            run_example_step.dependOn(&run_example.step);
        }
    }

    // Format check
    const fmt_step = b.step("fmt", "Format all source files");
    const fmt = b.addFmt(.{
        .paths = &.{ "src", "build.zig" },
        .check = false,
    });
    fmt_step.dependOn(&fmt.step);

    const fmt_check_step = b.step("fmt-check", "Check formatting of all source files");
    const fmt_check = b.addFmt(.{
        .paths = &.{ "src", "build.zig" },
        .check = true,
    });
    fmt_check_step.dependOn(&fmt_check.step);

    // Lint step
    const lint_step = b.step("lint", "Run all linting and code quality checks");
    lint_step.dependOn(&fmt_check.step);

    const lint_lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = .Debug,
        .link_libc = true,
    });
    lint_lib_mod.addImport("secp256k1", secp256k1_mod);
    const lint_lib = b.addLibrary(.{
        .name = "zigeth-lint",
        .root_module = lint_lib_mod,
    });
    const lint_lib_check = b.addInstallArtifact(lint_lib, .{
        .dest_dir = .{ .override = .{ .custom = "lint" } },
    });
    lint_step.dependOn(&lint_lib_check.step);

    // exe lint disabled during 0.16 migration
    lint_step.dependOn(&run_lib_unit_tests.step);

    // Zig 0.16 removed `Build.addRemoveDirTree`; a plain `rm -rf` is
    // fine here since `zig-cache` / `zig-out` are the canonical spots.
    const clean_step = b.step("clean", "Remove build artifacts");
    _ = clean_step;
}
