//! Native debug runner: a development tool, not a shipped artifact.
//!
//! The VM's real host is JavaScript, talking to `vm.wasm` (see io.zig). This
//! binary exists so the same `interpretSource` seam can be driven from a
//! terminal without a browser in the loop:
//!
//!     zig build run -- '1 + 2 * 3'
//!
//! With no argument it reads the whole program from stdin.

const std = @import("std");
const noka = @import("vm.zig");

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    // Joining argv means the unquoted `zig build run -- 1 + 2` works too, not
    // just the quoted form.
    const source = if (args.len > 1)
        try std.mem.join(arena, " ", args[1..])
    else
        try readAllStdin(init.io, arena);

    return @intCast(noka.interpretSource(source));
}

fn readAllStdin(io: std.Io, gpa: std.mem.Allocator) ![]u8 {
    var buf: [4096]u8 = undefined;
    var file_reader = std.Io.File.stdin().readerStreaming(io, &buf);
    return file_reader.interface.allocRemaining(gpa, .unlimited);
}
