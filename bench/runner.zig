//! Native benchmark runner, built ReleaseFast by `zig build bench`. Not a shipped artifact.
//!
//! bench.mjs drives it one program at a time:
//!
//!     runner check <file>         run once; the VM prints the program's value to stdout
//!     runner time <runs> <file> [machines]
//!                                 one warmup run, then <runs> timed runs; writes
//!                                 {"min_ns":N,"median_ns":N} to stderr. Each run evaluates the
//!                                 program in <machines> fresh machines (default 1).
//!
//! Timings go to stderr because the VM owns stdout.

const std = @import("std");
const noka = @import("noka_vm");

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const io = init.io;
    const args = try init.minimal.args.toSlice(arena);

    if (args.len == 3 and std.mem.eql(u8, args[1], "check")) {
        const source = try readProgram(io, arena, args[2]);
        return if (noka.interpretSource(source) == .failed) 1 else 0;
    }

    if ((args.len == 4 or args.len == 5) and std.mem.eql(u8, args[1], "time")) {
        const runs = try std.fmt.parseInt(usize, args[2], 10);
        const machines = if (args.len == 5) try std.fmt.parseInt(usize, args[4], 10) else 1;
        if (runs == 0 or machines == 0) return usage();
        const source = try readProgram(io, arena, args[3]);

        if (noka.interpretSource(source) == .failed) return 1;

        const samples = try arena.alloc(i96, runs);
        for (samples) |*sample| {
            const start = std.Io.Timestamp.now(io, .awake);
            for (0..machines) |_| {
                if (noka.interpretSource(source) == .failed) return 1;
            }
            sample.* = start.untilNow(io, .awake).toNanoseconds();
        }

        std.mem.sort(i96, samples, {}, std.sort.asc(i96));
        std.debug.print("{{\"min_ns\":{d},\"median_ns\":{d}}}\n", .{ samples[0], samples[runs / 2] });
        return 0;
    }

    return usage();
}

fn usage() u8 {
    std.debug.print("usage: runner check <file> | runner time <runs> <file> [machines]\n", .{});
    return 2;
}

/// Reads a benchmark program and drops its leading `//` header lines, which hold the metadata
/// bench.mjs reads (`iterations:`, `machines:`, `expect:`). The VM doesn't scan comments yet.
fn readProgram(io: std.Io, gpa: std.mem.Allocator, path: []const u8) ![]const u8 {
    const text = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(64 * 1024));

    var rest: []const u8 = text;
    while (std.mem.startsWith(u8, rest, "//")) {
        const eol = std.mem.indexOfScalar(u8, rest, '\n') orelse return rest[rest.len..];
        rest = rest[eol + 1 ..];
    }
    return rest;
}
