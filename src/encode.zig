const std = @import("std");
const types = @import("types.zig");
const png = @import("encode/png/writer.zig");
const jpeg = @import("encode/jpeg/writer.zig");

pub const ImageU8 = types.ImageU8;
pub const JpegEncodeOptions = jpeg.JpegEncodeOptions;
pub const PngTextEntry = png.PngTextEntry;
pub const PngEncodeOptions = png.PngEncodeOptions;

pub const EncodeError = types.ImageError || png.PngEncodeError || jpeg.JpegEncodeError;

pub fn encodePngAlloc(allocator: std.mem.Allocator, image: *const ImageU8) ![]u8 {
    return png.encodeAlloc(allocator, image);
}

pub fn encodePngAllocWithOptions(allocator: std.mem.Allocator, image: *const ImageU8, options: PngEncodeOptions) ![]u8 {
    return png.encodeAllocWithOptions(allocator, image, options);
}

pub fn writePng(allocator: std.mem.Allocator, writer: *std.Io.Writer, image: *const ImageU8) !void {
    return png.write(allocator, writer, image);
}

pub fn writePngWithOptions(allocator: std.mem.Allocator, writer: *std.Io.Writer, image: *const ImageU8, options: PngEncodeOptions) !void {
    return png.writeWithOptions(allocator, writer, image, options);
}

pub fn writePngFile(allocator: std.mem.Allocator, path: []const u8, image: *const ImageU8) !void {
    return png.writeFile(allocator, path, image);
}

pub fn writePngFileWithOptions(allocator: std.mem.Allocator, path: []const u8, image: *const ImageU8, options: PngEncodeOptions) !void {
    return png.writeFileWithOptions(allocator, path, image, options);
}

pub fn encodeJpegAlloc(allocator: std.mem.Allocator, image: *const ImageU8, options: JpegEncodeOptions) ![]u8 {
    return jpeg.encodeAlloc(allocator, image, options);
}

pub fn writeJpeg(allocator: std.mem.Allocator, writer: *std.Io.Writer, image: *const ImageU8, options: JpegEncodeOptions) !void {
    return jpeg.write(allocator, writer, image, options);
}

pub fn writeJpegFile(allocator: std.mem.Allocator, path: []const u8, image: *const ImageU8, options: JpegEncodeOptions) !void {
    return jpeg.writeFile(allocator, path, image, options);
}
