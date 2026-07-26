const std = @import("std");

pub const header_len = 48;
pub const capacity = 64 * 1024; // 64 KiB
pub const format_major = 1;

pub const Section = enum(u3) {
    meta,
    src,
    gfx,
    map,
    sfx,
    _,
};

pub const Entry = struct {
    offset: u16,
    len: u16,
};

pub const Header = struct {
    major: u8,
    minor: u8,
    patch: u8,
    flags: u8,
    payload_len: u32,
    stored_len: u32,
    sections: [8]Entry,

    pub fn section(self: Header, disc: []const u8, s: Section) ?[]const u8 {
        const entry = self.sections[@intFromEnum(s)];
        if (entry.len == 0) return null;

        return disc[header_len + entry.offset ..][0..entry.len];
    }
};

pub const ParseError = error{
    Truncated,
    BadVoodoo,
    UnsupportedVersion,
    Compressed,
    BadSection,
    DiscTooLarge,
};

pub fn parse(disc: []const u8) ParseError!Header {
    if (disc.len < header_len) return ParseError.Truncated;
    if (!std.mem.eql(u8, disc[0x00..0x04], "NOKA")) return ParseError.BadVoodoo;
    if (disc[0x04] != format_major) return ParseError.UnsupportedVersion;
    // TODO: warn about minor mismatch but no error
    // patch mismatch can be ignored entirely
    if (disc[0x07] & 0x01 != 0) return ParseError.Compressed;

    var header = Header{
        .major = disc[0x04],
        .minor = disc[0x05],
        .patch = disc[0x06],
        .flags = disc[0x07],
        .payload_len = std.mem.readInt(u32, disc[0x08..0x0C], .little),
        .stored_len = std.mem.readInt(u32, disc[0x0C..0x10], .little),
        .sections = undefined,
    };

    if (header.payload_len > capacity - header_len) return ParseError.DiscTooLarge;
    if (header_len + header.payload_len > disc.len) return ParseError.Truncated;

    for (0..8) |i| {
        const j = 0x10 + i * 4;
        const offset = std.mem.readInt(u16, disc[j..][0..2], .little);
        const len = std.mem.readInt(u16, disc[j + 2 ..][0..2], .little);

        if (@as(u32, offset) + @as(u32, len) <= header.payload_len) {
            header.sections[i] = .{ .offset = offset, .len = len };
        } else {
            return ParseError.BadSection;
        }
    }

    return header;
}

pub fn describe(e: ParseError) []const u8 {
    return switch (e) {
        .Truncated => "disc truncated",
        .BadVoodoo => "invalid magic header",
        .UnsupportedVersion => "unsupported major version",
        .Compressed => "compressed disc not supported yet",
        .BadSection => "section extends past payload",
        .DiscTooLarge => "disk too large",
    };
}

// --- TESTS ------------------------------------------------------------------

const testing = @import("std").testing;

// build a good disc from a given src
fn fixture(buf: []u8, src: []const u8) []u8 {
    @memset(buf[0..header_len], 0);
    @memcpy(buf[0..4], "NOKA"); // good voodoo
    buf[0x04] = 1; // major version
    buf[0x05] = 0; // minor version
    buf[0x06] = 0; // patch
    buf[0x07] = 0; // flag
    std.mem.writeInt(u32, buf[0x08..0x0C], @intCast(src.len), .little); // payload length
    std.mem.writeInt(u32, buf[0x0C..0x10], @intCast(src.len), .little); // stored length
    std.mem.writeInt(u16, buf[0x14..0x16], 0, .little); // src offset
    std.mem.writeInt(u16, buf[0x16..0x18], @intCast(src.len), .little); // src length
    @memcpy(buf[header_len..][0..src.len], src);

    return buf[0 .. header_len + src.len];
}

test "parse with good disc" {
    const src = "1 + 2 * 3";
    var buf: [100]u8 = undefined;
    const disc = fixture(&buf, src);

    const header = try parse(disc);
    try testing.expectEqualStrings(src, header.section(disc, .src).?);
}

test "parse with bad voodoo" {
    const src = "1 + 2 * 3";
    var buf: [100]u8 = undefined;
    const disc = fixture(&buf, src);
    @memcpy(disc[0..4], "KANO");

    try testing.expectError(ParseError.BadVoodoo, parse(disc));
}

test "parse with bad major version" {
    const src = "1 + 2 * 3";
    var buf: [100]u8 = undefined;
    const disc = fixture(&buf, src);
    disc[0x04] = 99;

    try testing.expectError(ParseError.UnsupportedVersion, parse(disc));
}

test "parse with bad flag" {
    const src = "1 + 2 * 3";
    var buf: [100]u8 = undefined;
    const disc = fixture(&buf, src);
    disc[0x07] = 1;

    try testing.expectError(ParseError.Compressed, parse(disc));
}

test "parse with bad section" {
    const src = "1 + 2 * 3";
    var buf: [100]u8 = undefined;
    const disc = fixture(&buf, src);
    std.mem.writeInt(u16, disc[0x14..0x16], 65000, .little);
    std.mem.writeInt(u16, disc[0x16..0x18], 1000, .little);

    try testing.expectError(ParseError.BadSection, parse(disc));
}

test "parse with truncated disc" {
    const src = "1 + 2 * 3";
    var buf: [100]u8 = undefined;
    const disc = fixture(&buf, src);
    disc[0x08] = 255;

    try testing.expectError(ParseError.Truncated, parse(disc));
}

test "parse with truncated header" {
    var buf: [100]u8 = undefined;
    const disc = fixture(&buf, "");

    try testing.expectError(ParseError.Truncated, parse(disc[0..10]));
}

test "parse with disc too large" {
    var buf: [100]u8 = undefined;
    const disc = fixture(&buf, "");
    std.mem.writeInt(u32, disc[0x08..0x0C], @intCast(capacity), .little);

    try testing.expectError(ParseError.DiscTooLarge, parse(disc));
}

test "absent section returns null" {
    const src = "1 + 2 * 3";
    var buf: [100]u8 = undefined;
    const disc = fixture(&buf, src);

    const header = try parse(disc);
    try testing.expect(header.section(disc, .gfx) == null);
}
