const std = @import("std");

pub const png_signature = "\x89PNG\r\n\x1a\n";

pub fn writeSignature(writer: *std.Io.Writer) !void {
    try writer.writeAll(png_signature);
}

pub fn writeChunk(writer: *std.Io.Writer, chunk_type: [4]u8, data: []const u8) !void {
    var len_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &len_bytes, @intCast(data.len), .big);
    try writer.writeAll(&len_bytes);
    try writer.writeAll(&chunk_type);
    try writer.writeAll(data);

    var crc = std.hash.Crc32.init();
    crc.update(&chunk_type);
    crc.update(data);

    var crc_bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &crc_bytes, crc.final(), .big);
    try writer.writeAll(&crc_bytes);
}

pub fn writeIhdr(
    writer: *std.Io.Writer,
    width: usize,
    height: usize,
    bit_depth: u8,
    color_type: u8,
) !void {
    var ihdr: [13]u8 = undefined;
    std.mem.writeInt(u32, ihdr[0..4], @intCast(width), .big);
    std.mem.writeInt(u32, ihdr[4..8], @intCast(height), .big);
    ihdr[8] = bit_depth;
    ihdr[9] = color_type;
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;
    try writeChunk(writer, .{ 'I', 'H', 'D', 'R' }, &ihdr);
}

pub fn writeIend(writer: *std.Io.Writer) !void {
    try writeChunk(writer, .{ 'I', 'E', 'N', 'D' }, &.{});
}
