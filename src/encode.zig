const std = @import("std");
const types = @import("types.zig");
const png = @import("encode/png/writer.zig");

pub const ImageU8 = types.ImageU8;

pub const EncodeError = types.ImageError || png.PngEncodeError;

pub fn encodePngAlloc(allocator: std.mem.Allocator, image: *const ImageU8) ![]u8 {
    return png.encodeAlloc(allocator, image);
}

pub fn writePng(allocator: std.mem.Allocator, writer: *std.Io.Writer, image: *const ImageU8) !void {
    return png.write(allocator, writer, image);
}

pub fn writePngFile(allocator: std.mem.Allocator, path: []const u8, image: *const ImageU8) !void {
    return png.writeFile(allocator, path, image);
}
