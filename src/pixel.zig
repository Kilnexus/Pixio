const types = @import("types.zig");

pub const ImageError = types.ImageError;

pub const PixelFormat = enum {
    gray8,
    rgb8,
    rgba8,

    pub fn channelCount(self: PixelFormat) usize {
        return switch (self) {
            .gray8 => 1,
            .rgb8 => 3,
            .rgba8 => 4,
        };
    }

    pub fn hasAlpha(self: PixelFormat) bool {
        return self == .rgba8;
    }
};

pub const ColorSpace = enum {
    unknown,
    srgb,
    linear,
};

pub const AlphaMode = enum {
    opaque_pixels,
    straight,
    premultiplied,
};

pub const ImageDescriptor = struct {
    pixel_format: PixelFormat,
    color_space: ColorSpace = .unknown,
    alpha_mode: AlphaMode = .opaque_pixels,

    pub fn channelCount(self: ImageDescriptor) usize {
        return self.pixel_format.channelCount();
    }

    pub fn bytesPerPixel(self: ImageDescriptor) usize {
        return self.channelCount();
    }

    pub fn hasAlpha(self: ImageDescriptor) bool {
        return self.pixel_format.hasAlpha();
    }

    pub fn validate(self: ImageDescriptor) !void {
        if (self.hasAlpha()) {
            if (self.alpha_mode == .opaque_pixels) return error.InvalidImageDescriptor;
        } else if (self.alpha_mode != .opaque_pixels) {
            return error.InvalidImageDescriptor;
        }
    }
};

pub fn descriptorForChannels(channels: usize) !ImageDescriptor {
    return switch (channels) {
        1 => .{ .pixel_format = .gray8, .alpha_mode = .opaque_pixels },
        3 => .{ .pixel_format = .rgb8, .alpha_mode = .opaque_pixels },
        4 => .{ .pixel_format = .rgba8, .alpha_mode = .straight },
        else => error.InvalidPixelFormat,
    };
}
