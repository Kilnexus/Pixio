const std = @import("std");
const convert = @import("convert.zig");
const crop = @import("crop.zig");
const geometry = @import("geometry.zig");
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
pub const BoxF32 = geometry.BoxF32;
pub const CropRect = crop.CropRect;

pub const PreprocessMode = enum {
    fit,
    contain,
    letterbox,
    cover,
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

pub const PreparedImageBatch = struct {
    allocator: std.mem.Allocator,
    items: []PreparedImage,

    pub fn deinit(self: *PreparedImageBatch) void {
        for (self.items) |*item| item.deinit();
        self.allocator.free(self.items);
        self.* = undefined;
    }

    pub fn remapBoxes(self: *const PreparedImageBatch, index: usize, boxes: []BoxF32) void {
        for (boxes) |*box| remapBoxToSource(box, self.items[index].info);
    }
};

pub const PreparedTensorBatch = struct {
    allocator: std.mem.Allocator,
    items: []PreparedTensor,

    pub fn deinit(self: *PreparedTensorBatch) void {
        for (self.items) |*item| item.deinit();
        self.allocator.free(self.items);
        self.* = undefined;
    }

    pub fn remapBoxes(self: *const PreparedTensorBatch, index: usize, boxes: []BoxF32) void {
        for (boxes) |*box| remapBoxToSource(box, self.items[index].info);
    }
};

pub const TensorF32NCHW = types.TensorF32NCHW;

pub const PreparedTensorNCHWBatch = struct {
    allocator: std.mem.Allocator,
    infos: []PreprocessInfo,
    tensor: TensorF32NCHW,

    pub fn deinit(self: *PreparedTensorNCHWBatch) void {
        self.allocator.free(self.infos);
        self.tensor.deinit();
        self.* = undefined;
    }

    pub fn remapBoxes(self: *const PreparedTensorNCHWBatch, index: usize, boxes: []BoxF32) void {
        for (boxes) |*box| remapBoxToSource(box, self.infos[index]);
    }
};

pub const RoiInput = struct {
    image_index: usize,
    rect: CropRect,
};

pub const RoiPreprocessInfo = struct {
    image_index: usize,
    roi: CropRect,
    preprocess: PreprocessInfo,
};

pub const PreparedRoiTensorNCHWBatch = struct {
    allocator: std.mem.Allocator,
    infos: []RoiPreprocessInfo,
    tensor: TensorF32NCHW,

    pub fn deinit(self: *PreparedRoiTensorNCHWBatch) void {
        self.allocator.free(self.infos);
        self.tensor.deinit();
        self.* = undefined;
    }

    pub fn remapBoxes(self: *const PreparedRoiTensorNCHWBatch, index: usize, boxes: []BoxF32) void {
        const info = self.infos[index];
        for (boxes) |*box| {
            remapBoxToSource(box, info.preprocess);
            box.x1 += @floatFromInt(info.roi.x);
            box.y1 += @floatFromInt(info.roi.y);
            box.x2 += @floatFromInt(info.roi.x);
            box.y2 += @floatFromInt(info.roi.y);
        }
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
        .cover => prepareCover(allocator, &converted, src, options),
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

pub fn prepareImageBatch(
    allocator: std.mem.Allocator,
    sources: []const *const ImageU8,
    options: PreprocessOptions,
) !PreparedImageBatch {
    var items = try allocator.alloc(PreparedImage, sources.len);
    errdefer allocator.free(items);

    var built: usize = 0;
    errdefer {
        for (items[0..built]) |*item| item.deinit();
    }

    for (sources, 0..) |src, i| {
        items[i] = try prepareImage(allocator, src, options);
        built += 1;
    }

    return .{
        .allocator = allocator,
        .items = items,
    };
}

pub fn prepareTensorBatch(
    allocator: std.mem.Allocator,
    sources: []const *const ImageU8,
    options: PreprocessOptions,
) !PreparedTensorBatch {
    var items = try allocator.alloc(PreparedTensor, sources.len);
    errdefer allocator.free(items);

    var built: usize = 0;
    errdefer {
        for (items[0..built]) |*item| item.deinit();
    }

    for (sources, 0..) |src, i| {
        items[i] = try prepareTensor(allocator, src, options);
        built += 1;
    }

    return .{
        .allocator = allocator,
        .items = items,
    };
}

pub fn prepareTensorNchwBatch(
    allocator: std.mem.Allocator,
    sources: []const *const ImageU8,
    options: PreprocessOptions,
) !PreparedTensorNCHWBatch {
    if (sources.len == 0) return error.InvalidBatchSize;

    const infos = try allocator.alloc(PreprocessInfo, sources.len);
    errdefer allocator.free(infos);

    var first = try prepareImage(allocator, sources[0], options);
    defer first.deinit();

    infos[0] = first.info;

    var tensor_out = try tensor.initTensorBatchNchwF32(
        allocator,
        sources.len,
        first.image.channels,
        first.image.height,
        first.image.width,
    );
    errdefer tensor_out.deinit();

    tensor.writeTensorNchwSample(
        tensor_out.data[0..tensor_out.stride_n],
        &first.image,
        options.normalize,
        tensor_out.stride_c,
        tensor_out.stride_h,
    );

    for (sources[1..], 1..) |src, i| {
        var prepared = try prepareImage(allocator, src, options);
        defer prepared.deinit();

        if (prepared.image.width != tensor_out.width or prepared.image.height != tensor_out.height or prepared.image.channels != tensor_out.channels) {
            return error.ShapeMismatch;
        }

        infos[i] = prepared.info;
        const batch_offset = i * tensor_out.stride_n;
        tensor.writeTensorNchwSample(
            tensor_out.data[batch_offset ..][0..tensor_out.stride_n],
            &prepared.image,
            options.normalize,
            tensor_out.stride_c,
            tensor_out.stride_h,
        );
    }
    return .{
        .allocator = allocator,
        .infos = infos,
        .tensor = tensor_out,
    };
}

pub fn prepareRoiTensorNchwBatch(
    allocator: std.mem.Allocator,
    sources: []const *const ImageU8,
    rois: []const RoiInput,
    options: PreprocessOptions,
) !PreparedRoiTensorNCHWBatch {
    if (rois.len == 0) return error.InvalidBatchSize;

    const infos = try allocator.alloc(RoiPreprocessInfo, rois.len);
    errdefer allocator.free(infos);

    const first_roi = rois[0];
    if (first_roi.image_index >= sources.len) return error.InvalidCropBounds;
    var first_crop = try crop.cropRect(allocator, sources[first_roi.image_index], first_roi.rect);
    defer first_crop.deinit();
    var first_prepared = try prepareImage(allocator, &first_crop, options);
    defer first_prepared.deinit();

    infos[0] = .{
        .image_index = first_roi.image_index,
        .roi = first_roi.rect,
        .preprocess = first_prepared.info,
    };

    var tensor_out = try tensor.initTensorBatchNchwF32(
        allocator,
        rois.len,
        first_prepared.image.channels,
        first_prepared.image.height,
        first_prepared.image.width,
    );
    errdefer tensor_out.deinit();

    tensor.writeTensorNchwSample(
        tensor_out.data[0..tensor_out.stride_n],
        &first_prepared.image,
        options.normalize,
        tensor_out.stride_c,
        tensor_out.stride_h,
    );

    for (rois[1..], 1..) |roi, i| {
        if (roi.image_index >= sources.len) return error.InvalidCropBounds;
        var cropped = try crop.cropRect(allocator, sources[roi.image_index], roi.rect);
        defer cropped.deinit();
        var prepared = try prepareImage(allocator, &cropped, options);
        defer prepared.deinit();

        if (prepared.image.width != tensor_out.width or prepared.image.height != tensor_out.height or prepared.image.channels != tensor_out.channels) {
            return error.ShapeMismatch;
        }

        infos[i] = .{
            .image_index = roi.image_index,
            .roi = roi.rect,
            .preprocess = prepared.info,
        };
        const batch_offset = i * tensor_out.stride_n;
        tensor.writeTensorNchwSample(
            tensor_out.data[batch_offset ..][0..tensor_out.stride_n],
            &prepared.image,
            options.normalize,
            tensor_out.stride_c,
            tensor_out.stride_h,
        );
    }

    return .{
        .allocator = allocator,
        .infos = infos,
        .tensor = tensor_out,
    };
}

pub fn remapBoxesToSource(boxes: []BoxF32, info: PreprocessInfo) void {
    for (boxes) |*box| remapBoxToSource(box, info);
}

pub fn remapBoxToSource(box: *BoxF32, info: PreprocessInfo) void {
    switch (info.mode) {
        .fit, .contain => {
            remapScaledBox(box, info.scale_x, info.scale_y, info.src_width, info.src_height);
        },
        .letterbox => {
            geometry.remapLetterboxedBoxToSource(
                box,
                info.offset_x,
                info.offset_y,
                info.scale_x,
                info.scale_y,
                info.src_width,
                info.src_height,
            );
        },
        .cover => {
            geometry.remapCoveredBoxToSource(
                box,
                info.offset_x,
                info.offset_y,
                info.scale_x,
                info.scale_y,
                info.src_width,
                info.src_height,
            );
        },
    }
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

fn prepareCover(
    allocator: std.mem.Allocator,
    converted: *const ImageU8,
    src: *const ImageU8,
    options: PreprocessOptions,
) !PreparedImage {
    var scale = @max(
        @as(f32, @floatFromInt(options.target_width)) / @as(f32, @floatFromInt(converted.width)),
        @as(f32, @floatFromInt(options.target_height)) / @as(f32, @floatFromInt(converted.height)),
    );
    if (!options.allow_upscale) scale = @min(scale, 1.0);

    const resized_width = @max(@as(usize, 1), @as(usize, @intFromFloat(@round(@as(f32, @floatFromInt(converted.width)) * scale))));
    const resized_height = @max(@as(usize, 1), @as(usize, @intFromFloat(@round(@as(f32, @floatFromInt(converted.height)) * scale))));
    var resized = try resize.resizeWithKernel(allocator, converted, resized_width, resized_height, options.kernel);
    defer resized.deinit();

    const crop_left = if (resized_width > options.target_width) (resized_width - options.target_width) / 2 else 0;
    const crop_top = if (resized_height > options.target_height) (resized_height - options.target_height) / 2 else 0;
    const crop_width = @min(options.target_width, resized_width);
    const crop_height = @min(options.target_height, resized_height);

    var image = try ImageU8.init(allocator, crop_width, crop_height, resized.channels);
    errdefer image.deinit();

    for (0..crop_height) |y| {
        const src_offset = ((crop_top + y) * resized.width + crop_left) * resized.channels;
        const dst_offset = y * image.width * image.channels;
        const row_len = crop_width * image.channels;
        @memcpy(image.data[dst_offset .. dst_offset + row_len], resized.data[src_offset .. src_offset + row_len]);
    }

    return .{
        .image = image,
        .info = .{
            .mode = .cover,
            .src_width = src.width,
            .src_height = src.height,
            .request_width = options.target_width,
            .request_height = options.target_height,
            .output_width = image.width,
            .output_height = image.height,
            .resized_width = resized.width,
            .resized_height = resized.height,
            .offset_x = crop_left,
            .offset_y = crop_top,
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

fn remapScaledBox(
    box: *BoxF32,
    scale_x: f32,
    scale_y: f32,
    src_width: usize,
    src_height: usize,
) void {
    const width = @as(f32, @floatFromInt(src_width));
    const height = @as(f32, @floatFromInt(src_height));
    box.x1 = clipToRange(box.x1 / scale_x, 0.0, width);
    box.y1 = clipToRange(box.y1 / scale_y, 0.0, height);
    box.x2 = clipToRange(box.x2 / scale_x, 0.0, width);
    box.y2 = clipToRange(box.y2 / scale_y, 0.0, height);
}

fn clipToRange(value: f32, min_value: f32, max_value: f32) f32 {
    return @max(min_value, @min(max_value, value));
}
