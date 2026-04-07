const std = @import("std");
const transform = @import("transform.zig");
const types = @import("types.zig");

pub const ImageU8 = types.ImageU8;

pub fn jpegOrientation(bytes: []const u8) u8 {
    return parseJpegOrientation(bytes) orelse 1;
}

pub fn jpegOrientationFile(allocator: std.mem.Allocator, file: std.fs.File) !u8 {
    var soi: [2]u8 = undefined;
    if (try file.preadAll(&soi, 0) < soi.len or soi[0] != 0xff or soi[1] != 0xd8) return 1;

    var pos: u64 = 2;
    while (true) {
        const marker = try nextMarker(file, &pos) orelse return 1;
        if (marker == 0xd9 or marker == 0xda) return 1;
        if (marker >= 0xd0 and marker <= 0xd7) continue;

        var segment_len_bytes: [2]u8 = undefined;
        if (try file.preadAll(&segment_len_bytes, pos) < segment_len_bytes.len) return 1;
        const segment_len = readU16be(&segment_len_bytes);
        if (segment_len < 2) return 1;

        if (marker == 0xe1) {
            const payload_len = segment_len - 2;
            const payload = try allocator.alloc(u8, payload_len);
            defer allocator.free(payload);
            if (try file.preadAll(payload, pos + 2) < payload_len) return 1;
            return parseExifPayload(payload) orelse 1;
        }

        pos += segment_len;
    }
}

pub fn orientedDimensions(width: usize, height: usize, orientation: u8) [2]usize {
    return switch (orientation) {
        5, 6, 7, 8 => .{ height, width },
        else => .{ width, height },
    };
}

pub fn applyOrientation(allocator: std.mem.Allocator, src: *const ImageU8, orientation: u8) !ImageU8 {
    return transform.applyExifOrientation(allocator, src, orientation);
}

fn parseJpegOrientation(bytes: []const u8) ?u8 {
    if (bytes.len < 4 or bytes[0] != 0xff or bytes[1] != 0xd8) return null;

    var pos: usize = 2;
    while (pos + 1 < bytes.len) {
        while (pos < bytes.len and bytes[pos] != 0xff) : (pos += 1) {}
        if (pos + 1 >= bytes.len) break;
        while (pos < bytes.len and bytes[pos] == 0xff) : (pos += 1) {}
        if (pos >= bytes.len) break;

        const marker = bytes[pos];
        pos += 1;
        if (marker == 0xd9 or marker == 0xda) break;
        if (marker >= 0xd0 and marker <= 0xd7) continue;
        if (pos + 2 > bytes.len) break;

        const segment_len = readU16be(bytes[pos .. pos + 2]);
        if (segment_len < 2 or pos + segment_len > bytes.len) break;
        if (marker == 0xe1) return parseExifPayload(bytes[pos + 2 .. pos + segment_len]) orelse 1;

        pos += segment_len;
    }

    return null;
}

fn parseExifPayload(payload: []const u8) ?u8 {
    if (payload.len < 6 or !std.mem.eql(u8, payload[0..6], "Exif\x00\x00")) return null;
    const tiff = payload[6..];
    if (tiff.len < 8) return null;

    const endian = parseEndian(tiff[0..2]) orelse return null;
    if (readU16(tiff[2..4], endian) != 42) return null;
    const ifd0_offset = readU32(tiff[4..8], endian);
    if (ifd0_offset + 2 > tiff.len) return null;

    const ifd0 = tiff[ifd0_offset..];
    const entry_count = readU16(ifd0[0..2], endian);
    if (2 + @as(usize, entry_count) * 12 > ifd0.len) return null;

    for (0..entry_count) |i| {
        const entry = ifd0[2 + i * 12 .. 2 + (i + 1) * 12];
        const tag = readU16(entry[0..2], endian);
        if (tag != 0x0112) continue;
        const field_type = readU16(entry[2..4], endian);
        const count = readU32(entry[4..8], endian);
        if (field_type != 3 or count != 1) return null;
        const value = readU16(entry[8..10], endian);
        if (value >= 1 and value <= 8) return @intCast(value);
        return 1;
    }

    return null;
}

fn nextMarker(file: std.fs.File, pos: *u64) !?u8 {
    while (true) {
        const byte = try readByteAt(file, pos.*) orelse return null;
        if (byte == 0xff) break;
        pos.* += 1;
    }

    while (true) {
        pos.* += 1;
        const marker = try readByteAt(file, pos.*) orelse return null;
        if (marker != 0xff) {
            pos.* += 1;
            return marker;
        }
    }
}

fn readByteAt(file: std.fs.File, offset: u64) !?u8 {
    var byte: [1]u8 = undefined;
    const read = try file.preadAll(&byte, offset);
    if (read == 0) return null;
    return byte[0];
}

const Endian = enum { little, big };

fn parseEndian(bytes: []const u8) ?Endian {
    if (std.mem.eql(u8, bytes, "II")) return .little;
    if (std.mem.eql(u8, bytes, "MM")) return .big;
    return null;
}

fn readU16(bytes: []const u8, endian: Endian) u16 {
    return std.mem.readInt(u16, bytes[0..2], switch (endian) {
        .little => .little,
        .big => .big,
    });
}

fn readU32(bytes: []const u8, endian: Endian) usize {
    return std.mem.readInt(u32, bytes[0..4], switch (endian) {
        .little => .little,
        .big => .big,
    });
}

fn readU16be(bytes: []const u8) usize {
    return std.mem.readInt(u16, bytes[0..2], .big);
}
