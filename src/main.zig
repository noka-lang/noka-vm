//! Native debug runner: a development tool, not a shipped artifact.
//!
//! The VM's real host is JavaScript, talking to `vm.wasm` (see io.zig). This
//! binary exists so the same `interpretSource` seam can be driven from a
//! terminal without a browser in the loop:
//!
//!     noka -- '1 + 2 * 3'
//!     noka --disc <file>

const std = @import("std");
const noka = @import("noka_vm");

pub fn main(init: std.process.Init) !u8 {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    if (args.len > 1 and std.mem.eql(u8, args[1], "--disc")) {
        if (args.len < 3) {
            std.debug.print("usage: noka --disc <file>\n", .{});
            return 2;
        }
        const image = readDisc(init.io, arena, args[2]) catch |err| {
            std.debug.print("failed to read disc: {s}\n", .{@errorName(err)});
            return 2;
        };
        return @intCast(noka.interpretDisc(image));
    }

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

fn readDisc(io: std.Io, gpa: std.mem.Allocator, path: []const u8) ![]u8 {
    const f = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer f.close(io);

    var buf: [4096]u8 = undefined;
    var file_reader = f.readerStreaming(io, &buf);

    return file_reader.interface.allocRemaining(gpa, .unlimited);
}
