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
    try validateTensorInputs(src, options);

    const tensor = TensorF32CHW{
        .allocator = allocator,
        .channels = src.channels,
        .height = src.height,
        .width = src.width,
        .data = try allocator.alloc(f32, src.channels * src.height * src.width),
    };
    errdefer allocator.free(tensor.data);
    try writeTensorChwSlice(tensor.data, src, options);
    return tensor;
}

pub fn initTensorBatchNchwF32(
    allocator: std.mem.Allocator,
    batch: usize,
    channels: usize,
    height: usize,
    width: usize,
) !TensorF32NCHW {
    if (batch == 0) return error.InvalidBatchSize;
    if (channels == 0) return error.InvalidChannelCount;
    if (width == 0 or height == 0) return error.InvalidImageDimensions;

    const stride_w: usize = 1;
    const stride_h = width;
    const stride_c = height * stride_h;
    const stride_n = channels * stride_c;
    return .{
        .allocator = allocator,
        .batch = batch,
        .channels = channels,
        .height = height,
        .width = width,
        .stride_n = stride_n,
        .stride_c = stride_c,
        .stride_h = stride_h,
        .stride_w = stride_w,
        .data = try allocator.alloc(f32, batch * stride_n),
    };
}

pub fn toTensorBatchNchwF32(
    allocator: std.mem.Allocator,
    images: []const *const ImageU8,
    options: NormalizeOptions,
) !TensorF32NCHW {
    if (images.len == 0) return error.InvalidBatchSize;

    const first = images[0];
    try validateTensorInputs(first, options);

    for (images[1..]) |image| {
        if (image.width != first.width or image.height != first.height or image.channels != first.channels) {
            return error.ShapeMismatch;
        }
    }

    var tensor_out = try initTensorBatchNchwF32(allocator, images.len, first.channels, first.height, first.width);
    errdefer allocator.free(tensor_out.data);

    for (images, 0..) |image, batch_index| {
        writeTensorNchwSample(tensor_out.data[batch_index * tensor_out.stride_n ..][0..tensor_out.stride_n], image, options, tensor_out.stride_c, tensor_out.stride_h);
    }

    return tensor_out;
}

pub fn writeTensorChwSlice(
    dst: []f32,
    src: *const ImageU8,
    options: NormalizeOptions,
) !void {
    try validateTensorInputs(src, options);

    const plane = src.width * src.height;
    if (dst.len != src.channels * plane) return error.ShapeMismatch;
    const norm = buildFastNormalizePlan(src.channels, options);

    for (0..src.height) |y| {
        const pixel_offset = y * src.width;
        const row = src.data[y * src.width * src.channels ..][0 .. src.width * src.channels];
        for (0..src.width) |x| {
            const src_offset = x * src.channels;
            for (0..src.channels) |channel| {
                const dst_index = channel * plane + pixel_offset + x;
                dst[dst_index] = @as(f32, @floatFromInt(row[src_offset + channel])) * norm.scale[channel] + norm.bias[channel];
            }
        }
    }
}

pub fn writeTensorNchwSample(
    dst: []f32,
    src: *const ImageU8,
    options: NormalizeOptions,
    stride_c: usize,
    stride_h: usize,
) void {
    const row_pixels = src.width * src.channels;
    const norm = buildFastNormalizePlan(src.channels, options);
    for (0..src.height) |y| {
        const row = src.data[y * row_pixels ..][0..row_pixels];
        const pixel_offset = y * stride_h;
        for (0..src.width) |x| {
            const src_offset = x * src.channels;
            for (0..src.channels) |channel| {
                dst[channel * stride_c + pixel_offset + x] = @as(f32, @floatFromInt(row[src_offset + channel])) * norm.scale[channel] + norm.bias[channel];
            }
        }
    }
}

const FastNormalizePlan = struct {
    scale: [4]f32,
    bias: [4]f32,
};

fn buildFastNormalizePlan(channels: usize, options: NormalizeOptions) FastNormalizePlan {
    var plan = FastNormalizePlan{
        .scale = .{ 0.0, 0.0, 0.0, 0.0 },
        .bias = .{ 0.0, 0.0, 0.0, 0.0 },
    };
    for (0..@min(channels, 4)) |channel| {
        const inv_std = reciprocalStat(options.std, channel);
        plan.scale[channel] = options.scale * inv_std;
        plan.bias[channel] = -statValue(options.mean, channel) * inv_std;
    }
    return plan;
}

fn validateTensorInputs(src: *const ImageU8, options: NormalizeOptions) !void {
    if (src.width == 0 or src.height == 0) return error.InvalidImageDimensions;
    if (src.channels == 0) return error.InvalidChannelCount;
    try validateStats(src.channels, options.mean);
    try validateStats(src.channels, options.std);
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

fn reciprocalStat(values: []const f32, channel: usize) f32 {
    return 1.0 / statValueOrOne(values, channel);
}
