const std = @import("std");
const types = @import("types.zig");
const pixel = @import("pixel.zig");

pub const ImageU8 = types.ImageU8;
pub const ImageError = types.ImageError;
pub const ImageDescriptor = pixel.ImageDescriptor;

pub const ImageLayout = struct {
    width: usize,
    height: usize,
    row_stride: usize,
    descriptor: ImageDescriptor,

    pub fn initPacked(width: usize, height: usize, descriptor: ImageDescriptor) !ImageLayout {
        if (width == 0 or height == 0) return error.InvalidImageDimensions;
        try descriptor.validate();

        const row_stride = try std.math.mul(usize, width, descriptor.bytesPerPixel());
        _ = try std.math.mul(usize, row_stride, height);

        return .{
            .width = width,
            .height = height,
            .row_stride = row_stride,
            .descriptor = descriptor,
        };
    }

    pub fn byteLen(self: ImageLayout) !usize {
        if (self.width == 0 or self.height == 0) return error.InvalidImageDimensions;
        if (self.row_stride < self.width * self.descriptor.bytesPerPixel()) return error.InvalidImageLayout;
        return try std.math.mul(usize, self.row_stride, self.height);
    }
};

pub const ImageConstViewU8 = struct {
    data: []const u8,
    layout: ImageLayout,

    pub fn row(self: ImageConstViewU8, y: usize) []const u8 {
        const start = y * self.layout.row_stride;
        const end = start + self.layout.width * self.layout.descriptor.bytesPerPixel();
        return self.data[start..end];
    }

    pub fn pixelSlice(self: ImageConstViewU8, x: usize, y: usize) []const u8 {
        const bytes_per_pixel = self.layout.descriptor.bytesPerPixel();
        const start = y * self.layout.row_stride + x * bytes_per_pixel;
        return self.data[start .. start + bytes_per_pixel];
    }

    pub fn subview(self: ImageConstViewU8, x: usize, y: usize, width: usize, height: usize) !ImageConstViewU8 {
        if (width == 0 or height == 0) return error.InvalidImageDimensions;
        if (x >= self.layout.width or y >= self.layout.height) return error.InvalidCropBounds;
        if (width > self.layout.width - x or height > self.layout.height - y) return error.InvalidCropBounds;

        const bytes_per_pixel = self.layout.descriptor.bytesPerPixel();
        const start = y * self.layout.row_stride + x * bytes_per_pixel;
        const last_row_end = start + (height - 1) * self.layout.row_stride + width * bytes_per_pixel;
        if (last_row_end > self.data.len) return error.InvalidImageLayout;

        return .{
            .data = self.data[start..last_row_end],
            .layout = .{
                .width = width,
                .height = height,
                .row_stride = self.layout.row_stride,
                .descriptor = self.layout.descriptor,
            },
        };
    }
};

pub const ImageViewU8 = struct {
    data: []u8,
    layout: ImageLayout,

    pub fn constView(self: ImageViewU8) ImageConstViewU8 {
        return .{
            .data = self.data,
            .layout = self.layout,
        };
    }

    pub fn row(self: ImageViewU8, y: usize) []u8 {
        const start = y * self.layout.row_stride;
        const end = start + self.layout.width * self.layout.descriptor.bytesPerPixel();
        return self.data[start..end];
    }

    pub fn pixelSlice(self: ImageViewU8, x: usize, y: usize) []u8 {
        const bytes_per_pixel = self.layout.descriptor.bytesPerPixel();
        const start = y * self.layout.row_stride + x * bytes_per_pixel;
        return self.data[start .. start + bytes_per_pixel];
    }
};

pub fn constViewFromImage(image: *const ImageU8) !ImageConstViewU8 {
    const descriptor = try pixel.descriptorForChannels(image.channels);
    const layout = try ImageLayout.initPacked(image.width, image.height, descriptor);
    const byte_len = try layout.byteLen();
    if (image.data.len != byte_len) return error.InvalidImageLayout;

    return .{
        .data = image.data,
        .layout = layout,
    };
}

pub fn viewFromImage(image: *ImageU8) !ImageViewU8 {
    const descriptor = try pixel.descriptorForChannels(image.channels);
    const layout = try ImageLayout.initPacked(image.width, image.height, descriptor);
    const byte_len = try layout.byteLen();
    if (image.data.len != byte_len) return error.InvalidImageLayout;

    return .{
        .data = image.data,
        .layout = layout,
    };
}
