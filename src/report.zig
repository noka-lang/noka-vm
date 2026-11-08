//! Failed machines leave a crash report for the host to read.
//!
//! Each report line is UTF-8, containing the reason, the line number, the call stack depth N,
//! N lines of code, then the message (which takes the rest of the buffer).

const std = @import("std");

pub const size = 1024;

/// Why a machine failed: a panic type (see LANGUAGE.md), a compile error, or a bad disc.
// TODO: add the rest once something raises them
pub const Reason = enum { compile, disc, frozen, math, oom, type, undefined };

pub const Report = struct {
    bytes: [size]u8 = undefined,
    len: usize = 0,

    /// Overwrites the report. Messages that are too long get cut off.
    pub fn write(self: *Report, reason: Reason, comptime fmt: []const u8, args: anytype) void {
        var w: std.Io.Writer = .fixed(&self.bytes);
        // TODO: line number and call stack
        w.print("{s}\n0\n0\n", .{@tagName(reason)}) catch {};
        w.print(fmt, args) catch {};
        self.len = wholeCharacters(self.bytes[0..w.end]);
    }

    pub fn text(self: *const Report) []const u8 {
        return self.bytes[0..self.len];
    }
};

/// Returns the length of `bytes` without any UTF-8 sequence that the cut-off left incomplete.
fn wholeCharacters(bytes: []const u8) usize {
    var lead = bytes.len;
    while (lead > 0 and bytes[lead - 1] & 0b1100_0000 == 0b1000_0000) lead -= 1;
    if (lead == 0) return bytes.len;
    lead -= 1;

    const want = std.unicode.utf8ByteSequenceLength(bytes[lead]) catch return bytes.len;
    return if (bytes.len - lead < want) lead else bytes.len;
}
