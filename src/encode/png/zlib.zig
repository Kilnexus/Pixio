const std = @import("std");

pub fn encodeStoredAlloc(allocator: std.mem.Allocator, data: []const u8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try writeStored(&out.writer, data);
    return try out.toOwnedSlice();
}

pub fn writeStored(writer: *std.Io.Writer, data: []const u8) !void {
    try writer.writeAll(&[_]u8{ 0x78, 0x01 });

    var offset: usize = 0;
    while (offset < data.len) {
        const block_len = @min(@as(usize, 65_535), data.len - offset);
        const final_block: u8 = if (offset + block_len == data.len) 1 else 0;
        try writer.writeByte(final_block);

        var header: [4]u8 = undefined;
        const len_u16: u16 = @intCast(block_len);
        std.mem.writeInt(u16, header[0..2], len_u16, .little);
        std.mem.writeInt(u16, header[2..4], ~len_u16, .little);
        try writer.writeAll(&header);
        try writer.writeAll(data[offset .. offset + block_len]);
        offset += block_len;
    }

    var adler: std.hash.Adler32 = .{};
    adler.update(data);
    var checksum: [4]u8 = undefined;
    std.mem.writeInt(u32, &checksum, adler.adler, .big);
    try writer.writeAll(&checksum);
}
