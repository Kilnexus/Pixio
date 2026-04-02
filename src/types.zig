const std = @import("std");

pub const ImageError = error{
    InvalidImageDimensions,
    InvalidChannelCount,
    InvalidCropBounds,
    InvalidNormalizationSpec,
    InvalidPixelFormat,
    InvalidImageLayout,
    InvalidImageDescriptor,
    ShapeMismatch,
};

pub const ImageU8 = struct {
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    channels: usize,
    data: []u8,

    pub fn init(
        allocator: std.mem.Allocator,
        width: usize,
        height: usize,
        channels: usize,
    ) !ImageU8 {
        if (width == 0 or height == 0) return error.InvalidImageDimensions;
        if (channels == 0) return error.InvalidChannelCount;

        return .{
            .allocator = allocator,
            .width = width,
            .height = height,
            .channels = channels,
            .data = try allocator.alloc(u8, width * height * channels),
        };
    }

    pub fn deinit(self: *ImageU8) void {
        self.allocator.free(self.data);
        self.* = undefined;
    }

    pub fn fill(self: *ImageU8, value: u8) void {
        @memset(self.data, value);
    }

    pub fn pixelIndex(self: *const ImageU8, x: usize, y: usize, channel: usize) usize {
        return (y * self.width + x) * self.channels + channel;
    }

    pub fn get(self: *const ImageU8, x: usize, y: usize, channel: usize) u8 {
        return self.data[self.pixelIndex(x, y, channel)];
    }

    pub fn set(self: *ImageU8, x: usize, y: usize, channel: usize, value: u8) void {
        self.data[self.pixelIndex(x, y, channel)] = value;
    }
};

pub fn toOpaqueRgba8(allocator: std.mem.Allocator, src: *const ImageU8) !ImageU8 {
    if (src.channels != 3) return error.InvalidChannelCount;

    var dst = try ImageU8.init(allocator, src.width, src.height, 4);
    errdefer dst.deinit();

    for (0..src.width * src.height) |i| {
        const src_index = i * 3;
        const dst_index = i * 4;
        dst.data[dst_index] = src.data[src_index];
        dst.data[dst_index + 1] = src.data[src_index + 1];
        dst.data[dst_index + 2] = src.data[src_index + 2];
        dst.data[dst_index + 3] = 0xff;
    }

    return dst;
}

pub const TensorF32CHW = struct {
    allocator: std.mem.Allocator,
    channels: usize,
    height: usize,
    width: usize,
    data: []f32,

    pub fn deinit(self: *TensorF32CHW) void {
        self.allocator.free(self.data);
        self.* = undefined;
    }
};
