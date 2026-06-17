const std = @import("std");

extern "env" fn host_print(ptr: [*]const u8, len: usize) void;

var heap_buffer: [1 << 20]u8 = undefined; // 1 MiB
var fba = std.heap.FixedBufferAllocator.init(&heap_buffer);
var scratch: [64 * 1024]u8 = undefined; // 64 Kib

export fn scratch_ptr() [*]u8 {
    return &scratch;
}

export fn scratch_cap() usize {
    return scratch.len;
}

export fn init() void {
    fba.reset();
}

fn print(s: []const u8) void {
    host_print(s.ptr, s.len);
}

/// Compile + run one chunk of source code.
/// Returns 0 on success, non-zero on error.
///
/// Right now this just echoes the input to prove the round-trip works.
export fn interpret(len: usize) i32 {
    const source = scratch[0..len];

    // TODO: real implementation.
    print("you typed: ");
    print(source);
    print("\n");

    return 0;
}
