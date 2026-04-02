const std = @import("std");
const types = @import("types.zig");

pub const ImageU8 = types.ImageU8;

pub const CropRect = struct {
    x: usize,
    y: usize,
    width: usize,
    height: usize,
};

pub fn crop(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    x: usize,
    y: usize,
    width: usize,
    height: usize,
) !ImageU8 {
    return cropRect(allocator, src, .{
        .x = x,
        .y = y,
        .width = width,
        .height = height,
    });
}

pub fn cropRect(allocator: std.mem.Allocator, src: *const ImageU8, rect: CropRect) !ImageU8 {
    if (src.width == 0 or src.height == 0 or rect.width == 0 or rect.height == 0) {
        return error.InvalidImageDimensions;
    }
    if (src.channels == 0) return error.InvalidChannelCount;
    if (rect.x >= src.width or rect.y >= src.height) return error.InvalidCropBounds;
    if (rect.width > src.width - rect.x or rect.height > src.height - rect.y) return error.InvalidCropBounds;

    var dst = try ImageU8.init(allocator, rect.width, rect.height, src.channels);
    errdefer dst.deinit();

    for (0..rect.height) |row| {
        const src_offset = ((rect.y + row) * src.width + rect.x) * src.channels;
        const dst_offset = row * rect.width * src.channels;
        const row_len = rect.width * src.channels;
        @memcpy(dst.data[dst_offset .. dst_offset + row_len], src.data[src_offset .. src_offset + row_len]);
    }

    return dst;
}
