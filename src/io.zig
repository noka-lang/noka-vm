const std = @import("std");
const builtin = @import("builtin");

/// The machine that printed.
pub const Handle = *const anyopaque;

/// On WASM, output is a callback into JavaScript, because WASM can't write to a console on its own.
/// Natively, there is no host to call into, so output goes to stdout.
/// This switch lets us just call `print()` and not have to worry about the platform we're on.
const sink = switch (builtin.target.cpu.arch) {
    .wasm32, .wasm64 => struct {
        extern "env" fn noka_host_print(m: Handle, ptr: [*]const u8, len: usize) void;

        fn write(m: Handle, s: []const u8) void {
            noka_host_print(m, s.ptr, s.len);
        }
    },
    else => struct {
        fn write(m: Handle, s: []const u8) void {
            _ = m;
            std.Io.File.stdout().writeStreamingAll(std.Options.debug_io, s) catch {};
        }
    },
};

pub fn print(m: Handle, s: []const u8) void {
    if (capture_enabled and capturing) {
        if (capture_from == null or capture_from == m) capture_buf.appendSlice(s);
        return;
    }
    sink.write(m, s);
}

// Single-threaded WASM, so one shared scratch buffer for formatting is fine.
var fmt_buf: [512]u8 = undefined;

pub fn printf(m: Handle, comptime fmt: []const u8, args: anytype) void {
    const s = std.fmt.bufPrint(&fmt_buf, fmt, args) catch return;
    print(m, s);
}

// ---- FOR TESTING -------------------------------------------------------------------------------
// Tests need to assert on what the VM printed, but `print` returns nothing to inspect. We need to
// divert the output into a buffer instead.

const capture_enabled = builtin.is_test;

var capturing = false;
var capture_from: ?Handle = null;
var capture_buf: Buf = .{};

const Buf = struct {
    bytes: [4096]u8 = undefined,
    len: usize = 0,

    fn appendSlice(self: *Buf, s: []const u8) void {
        const n = @min(self.bytes.len - self.len, s.len);
        @memcpy(self.bytes[self.len..][0..n], s[0..n]);
        self.len += n;
    }
};

/// Captures what every machine prints.
pub fn beginCapture() void {
    capture_buf.len = 0;
    capture_from = null;
    capturing = true;
}

/// Captures only what machine `m` prints.
pub fn beginCaptureFrom(m: Handle) void {
    beginCapture();
    capture_from = m;
}

pub fn captured() []const u8 {
    return capture_buf.bytes[0..capture_buf.len];
}

pub fn endCapture() void {
    capturing = false;
}
