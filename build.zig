const std = @import("std");
const default_sync_dest = "../nokascript/src/core/vm.wasm";

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();
    options.addOption(bool, "gc_stress", b.option(bool, "gc-stress", "Collect garbage at every point that can collect") orelse false);

    const vm = b.addModule("noka_vm", .{
        .root_source_file = b.path("src/vm.zig"),
        .target = target,
        .optimize = optimize,
    });

    vm.addOptions("build_options", options);

    // ---- NOT A SHIPPED ARTIFACT ----------------------------------------------------------------
    // It exists so `zig build run -- '1 + 2'` can drive the VM from a terminal
    const exe = b.addExecutable(.{
        .name = "noka",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "noka_vm", .module = vm }},
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();

    const run_step = b.step("run", "Evaluate a program natively: zig build run -- '1 + 2'");
    run_step.dependOn(&run_cmd.step);

    // ---- zig build forge -----------------------------------------------------------------------
    // TODO: add a `zig build forge` step wrapping `forgeDisc` to generate test discs from the terminal

    // ---- zig build test ------------------------------------------------------------------------
    const vm_tests = b.addTest(.{ .root_module = vm });
    const exe_tests = b.addTest(.{ .root_module = exe.root_module });

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&b.addRunArtifact(vm_tests).step);
    test_step.dependOn(&b.addRunArtifact(exe_tests).step);

    // ---- zig build wasm: ship this artifact! ---------------------------------------------------
    const wasm = b.addExecutable(.{
        .name = "vm",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/vm.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = .freestanding,
            }),
            .optimize = .ReleaseSmall,
        }),
    });
    wasm.root_module.addOptions("build_options", options);
    wasm.entry = .disabled;
    wasm.rdynamic = true;

    const install_wasm = b.addInstallArtifact(wasm, .{
        .dest_dir = .{ .override = .{ .custom = "lib" } },
    });

    const wasm_step = b.step("wasm", "Build the release artifact at zig-out/vm.wasm");
    wasm_step.dependOn(&install_wasm.step);

    // ---- zig build sync ------------------------------------------------------------------------
    // For quick local iteration only. Releasing is done via pushing a version tag.
    const sync_dest = b.option(
        []const u8,
        "sync-dest",
        "Path `zig build sync` copies vm.wasm to (default: " ++ default_sync_dest ++ ")",
    ) orelse default_sync_dest;

    const sync = b.addUpdateSourceFiles();
    sync.addCopyFileToSource(wasm.getEmittedBin(), sync_dest);

    const sync_step = b.step("sync", "Build vm.wasm and copy it into a sibling nokascript checkout");
    sync_step.dependOn(&install_wasm.step);
    sync_step.dependOn(&sync.step);

    // ---- zig build bench -----------------------------------------------------------------------
    // Times bench/programs natively (ReleaseFast) and as the shipped vm.wasm (in Node), then
    // compares against bench/baseline.json. Pass `-- --update` to rewrite the baseline.
    const bench_vm = b.createModule(.{
        .root_source_file = b.path("src/vm.zig"),
        .target = target,
        .optimize = .ReleaseFast,
    });
    bench_vm.addOptions("build_options", options);

    const bench_runner = b.addExecutable(.{
        .name = "bench-runner",
        .root_module = b.createModule(.{
            .root_source_file = b.path("bench/runner.zig"),
            .target = target,
            .optimize = .ReleaseFast,
            .imports = &.{.{ .name = "noka_vm", .module = bench_vm }},
        }),
    });

    const bench = b.addSystemCommand(&.{ "node", "bench/bench.mjs" });
    bench.addArg("--runner");
    bench.addArtifactArg(bench_runner);
    bench.addArg("--wasm");
    bench.addFileArg(wasm.getEmittedBin());
    bench.addPassthruArgs();

    const bench_step = b.step("bench", "Benchmark bench/programs natively and as vm.wasm against the baseline");
    bench_step.dependOn(&bench.step);

    // ---- zig build spec ------------------------------------------------------------------------
    // Runs every LANGUAGE.md code block against spec/manifest.json through the native runner.
    // Pass `-- --update` to sync the pending flags, `-- -v` to list every block.
    const spec = b.addSystemCommand(&.{ "node", "spec/spec.mjs" });
    spec.addArg("--noka");
    spec.addArtifactArg(exe);
    spec.addPassthruArgs();

    const spec_step = b.step("spec", "Run every LANGUAGE.md example against spec/manifest.json");
    spec_step.dependOn(&spec.step);

    // ---- zig build fuzz ------------------------------------------------------------------------
    // Replays fuzz/corpus, then runs random programs through the Debug runner and vm.wasm,
    // saving any crash to the corpus. Pass `-- --count N` or `-- --seed N`.
    const fuzz = b.addSystemCommand(&.{ "node", "fuzz/fuzz.mjs" });
    fuzz.addArg("--noka");
    fuzz.addArtifactArg(exe);
    fuzz.addArg("--wasm");
    fuzz.addFileArg(wasm.getEmittedBin());
    fuzz.addPassthruArgs();

    const fuzz_step = b.step("fuzz", "Fuzz the VM natively (Debug) and as vm.wasm, keeping crashes in fuzz/corpus");
    fuzz_step.dependOn(&fuzz.step);
}
