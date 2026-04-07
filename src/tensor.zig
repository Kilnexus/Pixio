const std = @import("std");
const types = @import("types.zig");

pub const ImageU8 = types.ImageU8;
pub const TensorF32CHW = types.TensorF32CHW;
pub const TensorF32NCHW = types.TensorF32NCHW;

pub const NormalizeOptions = struct {
    scale: f32 = 1.0 / 255.0,
    mean: []const f32 = &.{},
    std: []const f32 = &.{},
};

pub fn toTensorChwF32(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    options: NormalizeOptions,
) !TensorF32CHW {
    if (src.width == 0 or src.height == 0) return error.InvalidImageDimensions;
    if (src.channels == 0) return error.InvalidChannelCount;
    try validateStats(src.channels, options.mean);
    try validateStats(src.channels, options.std);

    var tensor = TensorF32CHW{
        .allocator = allocator,
        .channels = src.channels,
        .height = src.height,
        .width = src.width,
        .data = try allocator.alloc(f32, src.channels * src.height * src.width),
    };
    errdefer allocator.free(tensor.data);

    for (0..src.channels) |channel| {
        const mean = statValue(options.mean, channel);
        const inv_std = 1.0 / statValueOrOne(options.std, channel);
        const channel_offset = channel * src.width * src.height;
        for (0..src.height) |y| {
            for (0..src.width) |x| {
                const src_index = (y * src.width + x) * src.channels + channel;
                const dst_index = channel_offset + y * src.width + x;
                const scaled = @as(f32, @floatFromInt(src.data[src_index])) * options.scale;
                tensor.data[dst_index] = (scaled - mean) * inv_std;
            }
        }
    }

    return tensor;
}

pub fn toTensorBatchNchwF32(
    allocator: std.mem.Allocator,
    images: []const *const ImageU8,
    options: NormalizeOptions,
) !TensorF32NCHW {
    if (images.len == 0) return error.InvalidBatchSize;

    const first = images[0];
    if (first.width == 0 or first.height == 0) return error.InvalidImageDimensions;
    if (first.channels == 0) return error.InvalidChannelCount;
    try validateStats(first.channels, options.mean);
    try validateStats(first.channels, options.std);

    for (images[1..]) |image| {
        if (image.width != first.width or image.height != first.height or image.channels != first.channels) {
            return error.ShapeMismatch;
        }
    }

    const stride_w: usize = 1;
    const stride_h = first.width;
    const stride_c = first.height * stride_h;
    const stride_n = first.channels * stride_c;
    const total_len = images.len * stride_n;

    var tensor_out = TensorF32NCHW{
        .allocator = allocator,
        .batch = images.len,
        .channels = first.channels,
        .height = first.height,
        .width = first.width,
        .stride_n = stride_n,
        .stride_c = stride_c,
        .stride_h = stride_h,
        .stride_w = stride_w,
        .data = try allocator.alloc(f32, total_len),
    };
    errdefer allocator.free(tensor_out.data);

    for (images, 0..) |image, batch_index| {
        const batch_offset = batch_index * stride_n;
        for (0..image.channels) |channel| {
            const mean = statValue(options.mean, channel);
            const inv_std = 1.0 / statValueOrOne(options.std, channel);
            const channel_offset = batch_offset + channel * stride_c;
            for (0..image.height) |y| {
                for (0..image.width) |x| {
                    const src_index = (y * image.width + x) * image.channels + channel;
                    const dst_index = channel_offset + y * stride_h + x;
                    const scaled = @as(f32, @floatFromInt(image.data[src_index])) * options.scale;
                    tensor_out.data[dst_index] = (scaled - mean) * inv_std;
                }
            }
        }
    }

    return tensor_out;
}

fn validateStats(channels: usize, values: []const f32) !void {
    if (values.len == 0 or values.len == 1 or values.len == channels) return;
    return error.InvalidNormalizationSpec;
}

fn statValue(values: []const f32, channel: usize) f32 {
    if (values.len == 0) return 0.0;
    if (values.len == 1) return values[0];
    return values[channel];
}

fn statValueOrOne(values: []const f32, channel: usize) f32 {
    if (values.len == 0) return 1.0;
    if (values.len == 1) return values[0];
    return values[channel];
}
