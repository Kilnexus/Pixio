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
