const std = @import("std");
const resize = @import("resize.zig");
const types = @import("types.zig");

pub const ImageU8 = types.ImageU8;
pub const ResizeKernel = resize.ResizeKernel;

pub const FitOptions = struct {
    kernel: ResizeKernel = .bilinear,
};

pub const ContainOptions = struct {
    kernel: ResizeKernel = .bilinear,
    allow_upscale: bool = true,
};

pub fn fit(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    target_width: usize,
    target_height: usize,
    options: FitOptions,
) !ImageU8 {
    return resize.resizeWithKernel(allocator, src, target_width, target_height, options.kernel);
}

pub fn contain(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    max_width: usize,
    max_height: usize,
    options: ContainOptions,
) !ImageU8 {
    if (src.width == 0 or src.height == 0 or max_width == 0 or max_height == 0) {
        return error.InvalidImageDimensions;
    }
    if (src.channels == 0) return error.InvalidChannelCount;

    var scale = @min(
        @as(f32, @floatFromInt(max_width)) / @as(f32, @floatFromInt(src.width)),
        @as(f32, @floatFromInt(max_height)) / @as(f32, @floatFromInt(src.height)),
    );
    if (!options.allow_upscale) scale = @min(scale, 1.0);

    const dst_width = @max(@as(usize, 1), @as(usize, @intFromFloat(@round(@as(f32, @floatFromInt(src.width)) * scale))));
    const dst_height = @max(@as(usize, 1), @as(usize, @intFromFloat(@round(@as(f32, @floatFromInt(src.height)) * scale))));
    return resize.resizeWithKernel(allocator, src, dst_width, dst_height, options.kernel);
}

pub fn thumbnail(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    max_width: usize,
    max_height: usize,
    options: FitOptions,
) !ImageU8 {
    return contain(allocator, src, max_width, max_height, .{
        .kernel = options.kernel,
        .allow_upscale = false,
    });
}
