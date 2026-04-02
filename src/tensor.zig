const std = @import("std");
const types = @import("types.zig");

pub const ImageU8 = types.ImageU8;
pub const TensorF32CHW = types.TensorF32CHW;

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
