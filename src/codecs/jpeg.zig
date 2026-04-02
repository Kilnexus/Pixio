const std = @import("std");
const parser = @import("jpeg/parser.zig");
const jpeg_types = @import("jpeg/types.zig");
const image_types = @import("../types.zig");

pub const ImageU8 = jpeg_types.ImageU8;
pub const JpegError = jpeg_types.JpegError;

pub fn decodeRgb8(allocator: std.mem.Allocator, bytes: []const u8) !ImageU8 {
    return parser.decodeRgb8(allocator, bytes);
}

pub fn decodeRgba8(allocator: std.mem.Allocator, bytes: []const u8) !ImageU8 {
    var rgb = try decodeRgb8(allocator, bytes);
    defer rgb.deinit();
    return image_types.toOpaqueRgba8(allocator, &rgb);
}
