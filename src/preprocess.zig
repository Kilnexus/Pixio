const std = @import("std");
const convert = @import("convert.zig");
const fit_mod = @import("fit.zig");
const resize = @import("resize.zig");
const tensor = @import("tensor.zig");
const pixel = @import("pixel.zig");
const types = @import("types.zig");

pub const ImageU8 = types.ImageU8;
pub const TensorF32CHW = types.TensorF32CHW;
pub const PixelFormat = pixel.PixelFormat;
pub const ResizeKernel = resize.ResizeKernel;
pub const NormalizeOptions = tensor.NormalizeOptions;

pub const PreprocessMode = enum {
    fit,
    contain,
    letterbox,
};

pub const PreprocessInfo = struct {
    mode: PreprocessMode,
    src_width: usize,
    src_height: usize,
    request_width: usize,
    request_height: usize,
    output_width: usize,
    output_height: usize,
    resized_width: usize,
    resized_height: usize,
    offset_x: usize,
    offset_y: usize,
    scale_x: f32,
    scale_y: f32,
};

pub const PreprocessOptions = struct {
    target_width: usize,
    target_height: usize,
    mode: PreprocessMode = .letterbox,
    kernel: ResizeKernel = .bilinear,
    output_pixel_format: PixelFormat = .rgb8,
    pad_value: u8 = 0,
    allow_upscale: bool = true,
    normalize: NormalizeOptions = .{},
};

pub const PreparedImage = struct {
    image: ImageU8,
    info: PreprocessInfo,

    pub fn deinit(self: *PreparedImage) void {
        self.image.deinit();
        self.* = undefined;
    }
};

pub const PreparedTensor = struct {
    image: ImageU8,
    tensor: TensorF32CHW,
    info: PreprocessInfo,

    pub fn deinit(self: *PreparedTensor) void {
        self.image.deinit();
        self.tensor.deinit();
        self.* = undefined;
    }
};

pub fn prepareImage(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    options: PreprocessOptions,
) !PreparedImage {
    try validateOptions(src, options);

    var converted = try convert.toPixelFormat(allocator, src, options.output_pixel_format);
    defer converted.deinit();

    return switch (options.mode) {
        .fit => prepareFit(allocator, &converted, src, options),
        .contain => prepareContain(allocator, &converted, src, options),
        .letterbox => prepareLetterbox(allocator, &converted, src, options),
    };
}

pub fn prepareTensor(
    allocator: std.mem.Allocator,
    src: *const ImageU8,
    options: PreprocessOptions,
) !PreparedTensor {
    var prepared = try prepareImage(allocator, src, options);
    errdefer prepared.deinit();

    var tensor_out = try tensor.toTensorChwF32(allocator, &prepared.image, options.normalize);
    errdefer tensor_out.deinit();

    return .{
        .image = prepared.image,
        .tensor = tensor_out,
        .info = prepared.info,
    };
}

fn validateOptions(src: *const ImageU8, options: PreprocessOptions) !void {
    if (src.width == 0 or src.height == 0) return error.InvalidImageDimensions;
    if (src.channels == 0) return error.InvalidChannelCount;
    if (options.target_width == 0 or options.target_height == 0) return error.InvalidImageDimensions;
}

fn prepareFit(
    allocator: std.mem.Allocator,
    converted: *const ImageU8,
    src: *const ImageU8,
    options: PreprocessOptions,
) !PreparedImage {
    const image = try fit_mod.fit(allocator, converted, options.target_width, options.target_height, .{
        .kernel = options.kernel,
    });
    return .{
        .image = image,
        .info = .{
            .mode = .fit,
            .src_width = src.width,
            .src_height = src.height,
            .request_width = options.target_width,
            .request_height = options.target_height,
            .output_width = options.target_width,
            .output_height = options.target_height,
            .resized_width = options.target_width,
            .resized_height = options.target_height,
            .offset_x = 0,
            .offset_y = 0,
            .scale_x = @as(f32, @floatFromInt(options.target_width)) / @as(f32, @floatFromInt(src.width)),
            .scale_y = @as(f32, @floatFromInt(options.target_height)) / @as(f32, @floatFromInt(src.height)),
        },
    };
}

fn prepareContain(
    allocator: std.mem.Allocator,
    converted: *const ImageU8,
    src: *const ImageU8,
    options: PreprocessOptions,
) !PreparedImage {
    const image = try fit_mod.contain(allocator, converted, options.target_width, options.target_height, .{
        .kernel = options.kernel,
        .allow_upscale = options.allow_upscale,
    });
    return .{
        .image = image,
        .info = .{
            .mode = .contain,
            .src_width = src.width,
            .src_height = src.height,
            .request_width = options.target_width,
            .request_height = options.target_height,
            .output_width = image.width,
            .output_height = image.height,
            .resized_width = image.width,
            .resized_height = image.height,
            .offset_x = 0,
            .offset_y = 0,
            .scale_x = @as(f32, @floatFromInt(image.width)) / @as(f32, @floatFromInt(src.width)),
            .scale_y = @as(f32, @floatFromInt(image.height)) / @as(f32, @floatFromInt(src.height)),
        },
    };
}

fn prepareLetterbox(
    allocator: std.mem.Allocator,
    converted: *const ImageU8,
    src: *const ImageU8,
    options: PreprocessOptions,
) !PreparedImage {
    var resized = try fit_mod.contain(allocator, converted, options.target_width, options.target_height, .{
        .kernel = options.kernel,
        .allow_upscale = options.allow_upscale,
    });
    defer resized.deinit();

    const pad_left = (options.target_width - resized.width) / 2;
    const pad_top = (options.target_height - resized.height) / 2;

    var canvas = try ImageU8.init(allocator, options.target_width, options.target_height, resized.channels);
    errdefer canvas.deinit();
    fillCanvas(&canvas, options.output_pixel_format, options.pad_value);

    for (0..resized.height) |y| {
        const src_offset = y * resized.width * resized.channels;
        const dst_offset = ((pad_top + y) * canvas.width + pad_left) * canvas.channels;
        const row_len = resized.width * resized.channels;
        @memcpy(canvas.data[dst_offset .. dst_offset + row_len], resized.data[src_offset .. src_offset + row_len]);
    }

    return .{
        .image = canvas,
        .info = .{
            .mode = .letterbox,
            .src_width = src.width,
            .src_height = src.height,
            .request_width = options.target_width,
            .request_height = options.target_height,
            .output_width = options.target_width,
            .output_height = options.target_height,
            .resized_width = resized.width,
            .resized_height = resized.height,
            .offset_x = pad_left,
            .offset_y = pad_top,
            .scale_x = @as(f32, @floatFromInt(resized.width)) / @as(f32, @floatFromInt(src.width)),
            .scale_y = @as(f32, @floatFromInt(resized.height)) / @as(f32, @floatFromInt(src.height)),
        },
    };
}

fn fillCanvas(canvas: *ImageU8, format: PixelFormat, pad_value: u8) void {
    switch (format) {
        .gray8, .rgb8 => canvas.fill(pad_value),
        .rgba8 => {
            for (0..canvas.width * canvas.height) |i| {
                const base = i * 4;
                canvas.data[base] = pad_value;
                canvas.data[base + 1] = pad_value;
                canvas.data[base + 2] = pad_value;
                canvas.data[base + 3] = 0xff;
            }
        },
    }
}
