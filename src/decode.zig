const std = @import("std");
const types = @import("types.zig");
const format = @import("format.zig");
const png = @import("codecs/png.zig");
const bmp = @import("codecs/bmp.zig");
const jpeg = @import("codecs/jpeg.zig");
const gif = @import("codecs/gif.zig");
const ico = @import("codecs/ico.zig");
const webp = @import("codecs/webp.zig");
const exif = @import("exif.zig");

pub const ImageU8 = types.ImageU8;
pub const ImageFormat = format.ImageFormat;
pub const GifAnimation = gif.GifAnimation;
pub const GifAnimationFrame = gif.GifFrame;
pub const WebpAnimation = webp.Animation;
pub const WebpAnimationFrame = webp.AnimationFrame;

pub const DecodeError = types.ImageError || png.PngError || bmp.BmpError || jpeg.JpegError || gif.GifError || ico.IcoError || webp.WebpError || error{
    UnsupportedImageFormat,
    FileTooBig,
};

pub fn decodeRgb8(allocator: std.mem.Allocator, bytes: []const u8) !ImageU8 {
    return decodeWithChannels(allocator, bytes, 3);
}

pub fn decodeRgba8(allocator: std.mem.Allocator, bytes: []const u8) !ImageU8 {
    return decodeWithChannels(allocator, bytes, 4);
}

pub fn decodeReaderRgb8(allocator: std.mem.Allocator, reader: *std.Io.Reader) !ImageU8 {
    return decodeReaderWithChannels(allocator, reader, 3);
}

pub fn decodeReaderRgba8(allocator: std.mem.Allocator, reader: *std.Io.Reader) !ImageU8 {
    return decodeReaderWithChannels(allocator, reader, 4);
}

pub fn decodeFileRgb8(allocator: std.mem.Allocator, path: []const u8) !ImageU8 {
    return decodeFileWithChannels(allocator, path, 3);
}

pub fn decodeFileRgba8(allocator: std.mem.Allocator, path: []const u8) !ImageU8 {
    return decodeFileWithChannels(allocator, path, 4);
}

pub fn decodeGifFramesRgb8(allocator: std.mem.Allocator, bytes: []const u8) !GifAnimation {
    return try gif.decodeFramesRgb8(allocator, bytes);
}

pub fn decodeGifFramesRgba8(allocator: std.mem.Allocator, bytes: []const u8) !GifAnimation {
    return try gif.decodeFramesRgba8(allocator, bytes);
}

pub fn decodeFileGifFramesRgb8(allocator: std.mem.Allocator, path: []const u8) !GifAnimation {
    return try decodeFileGifFramesWithChannels(allocator, path, 3);
}

pub fn decodeFileGifFramesRgba8(allocator: std.mem.Allocator, path: []const u8) !GifAnimation {
    return try decodeFileGifFramesWithChannels(allocator, path, 4);
}

pub fn decodeWebpFramesRgb8(allocator: std.mem.Allocator, bytes: []const u8) !WebpAnimation {
    return try webp.decodeFramesRgb8(allocator, bytes);
}

pub fn decodeWebpFramesRgba8(allocator: std.mem.Allocator, bytes: []const u8) !WebpAnimation {
    return try webp.decodeFramesRgba8(allocator, bytes);
}

pub fn decodeFileWebpFramesRgb8(allocator: std.mem.Allocator, path: []const u8) !WebpAnimation {
    return try decodeFileWebpFramesWithChannels(allocator, path, 3);
}

pub fn decodeFileWebpFramesRgba8(allocator: std.mem.Allocator, path: []const u8) !WebpAnimation {
    return try decodeFileWebpFramesWithChannels(allocator, path, 4);
}

fn decodeWithChannels(allocator: std.mem.Allocator, bytes: []const u8, output_channels: usize) !ImageU8 {
    if (output_channels != 3 and output_channels != 4) return error.InvalidChannelCount;
    return switch (format.detectFormat(bytes)) {
        .png => if (output_channels == 4) png.decodeRgba8(allocator, bytes) else png.decodeRgb8(allocator, bytes),
        .bmp => if (output_channels == 4) bmp.decodeRgba8(allocator, bytes) else bmp.decodeRgb8(allocator, bytes),
        .jpeg => try decodeJpegAutoOriented(allocator, bytes, output_channels),
        .gif => if (output_channels == 4) gif.decodeRgba8(allocator, bytes) else gif.decodeRgb8(allocator, bytes),
        .ico => if (output_channels == 4) ico.decodeRgba8(allocator, bytes) else ico.decodeRgb8(allocator, bytes),
        .webp => if (output_channels == 4) webp.decodeRgba8(allocator, bytes) else webp.decodeRgb8(allocator, bytes),
        else => error.UnsupportedImageFormat,
    };
}

fn decodeReaderWithChannels(allocator: std.mem.Allocator, reader: *std.Io.Reader, output_channels: usize) !ImageU8 {
    const bytes = try std.Io.Reader.allocRemaining(reader, allocator, .unlimited);
    defer allocator.free(bytes);
    return decodeWithChannels(allocator, bytes, output_channels);
}

fn decodeFileWithChannels(allocator: std.mem.Allocator, path: []const u8, output_channels: usize) !ImageU8 {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    if (stat.size > std.math.maxInt(usize)) return error.FileTooBig;

    var header: [64]u8 = undefined;
    const header_len = try file.preadAll(&header, 0);
    return switch (format.detectFormat(header[0..header_len])) {
        .bmp => if (output_channels == 4) bmp.decodeFileRgba8(allocator, file) else bmp.decodeFileRgb8(allocator, file),
        else => blk: {
            var read_buffer: [16 * 1024]u8 = undefined;
            var file_reader = file.reader(&read_buffer);
            break :blk decodeReaderWithChannels(allocator, &file_reader.interface, output_channels);
        },
    };
}

fn decodeFileGifFramesWithChannels(
    allocator: std.mem.Allocator,
    path: []const u8,
    output_channels: usize,
) !GifAnimation {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    if (stat.size > std.math.maxInt(usize)) return error.FileTooBig;

    var reader_buffer: [16 * 1024]u8 = undefined;
    var reader = file.reader(&reader_buffer);
    const bytes = try std.Io.Reader.allocRemaining(&reader.interface, allocator, .unlimited);
    defer allocator.free(bytes);

    return switch (output_channels) {
        3 => try gif.decodeFramesRgb8(allocator, bytes),
        4 => try gif.decodeFramesRgba8(allocator, bytes),
        else => error.InvalidChannelCount,
    };
}

fn decodeFileWebpFramesWithChannels(
    allocator: std.mem.Allocator,
    path: []const u8,
    output_channels: usize,
) !WebpAnimation {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const stat = try file.stat();
    if (stat.size > std.math.maxInt(usize)) return error.FileTooBig;

    var reader_buffer: [16 * 1024]u8 = undefined;
    var reader = file.reader(&reader_buffer);
    const bytes = try std.Io.Reader.allocRemaining(&reader.interface, allocator, .unlimited);
    defer allocator.free(bytes);

    return switch (output_channels) {
        3 => try webp.decodeFramesRgb8(allocator, bytes),
        4 => try webp.decodeFramesRgba8(allocator, bytes),
        else => error.InvalidChannelCount,
    };
}

fn decodeJpegAutoOriented(allocator: std.mem.Allocator, bytes: []const u8, output_channels: usize) !ImageU8 {
    var rgb = try jpeg.decodeRgb8(allocator, bytes);
    errdefer rgb.deinit();

    const orientation = exif.jpegOrientation(bytes);
    if (orientation != 1) {
        const oriented = try exif.applyOrientation(allocator, &rgb, orientation);
        rgb.deinit();
        rgb = oriented;
    }

    if (output_channels == 3) return rgb;

    defer rgb.deinit();
    return types.toOpaqueRgba8(allocator, &rgb);
}
