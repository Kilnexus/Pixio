const std = @import("std");
const pixel = @import("../../pixel.zig");
const view_mod = @import("../../view.zig");
const types = @import("../../types.zig");
const container = @import("container.zig");
const filter = @import("filter.zig");
const zlib = @import("zlib.zig");

pub const ImageU8 = types.ImageU8;
pub const ImageConstViewU8 = view_mod.ImageConstViewU8;
pub const ImageDescriptor = pixel.ImageDescriptor;

pub const PngEncodeError = types.ImageError || error{
    UnsupportedPngEncodeFormat,
};

pub fn encodeAlloc(allocator: std.mem.Allocator, image: *const ImageU8) ![]u8 {
    const view = try view_mod.constViewFromImage(image);
    return encodeAllocView(allocator, view);
}

pub fn encodeAllocView(allocator: std.mem.Allocator, view: ImageConstViewU8) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try writeView(allocator, &out.writer, view);
    return try out.toOwnedSlice();
}

pub fn write(allocator: std.mem.Allocator, writer: *std.Io.Writer, image: *const ImageU8) !void {
    const view = try view_mod.constViewFromImage(image);
    try writeView(allocator, writer, view);
}

pub fn writeView(allocator: std.mem.Allocator, writer: *std.Io.Writer, view: ImageConstViewU8) !void {
    try view.layout.descriptor.validate();
    const color_type = try pngColorType(view.layout.descriptor);

    try container.writeSignature(writer);
    try container.writeIhdr(writer, view.layout.width, view.layout.height, 8, color_type);

    const filtered = try buildFilteredScanlines(allocator, view);
    defer allocator.free(filtered);

    const idat = try zlib.encodeStoredAlloc(allocator, filtered);
    defer allocator.free(idat);

    try container.writeChunk(writer, .{ 'I', 'D', 'A', 'T' }, idat);
    try container.writeIend(writer);
}

pub fn writeFile(allocator: std.mem.Allocator, path: []const u8, image: *const ImageU8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var buffer: [16 * 1024]u8 = undefined;
    var file_writer = file.writer(&buffer);
    try write(allocator, &file_writer.interface, image);
    try file_writer.interface.flush();
}

fn buildFilteredScanlines(allocator: std.mem.Allocator, view: ImageConstViewU8) ![]u8 {
    const filtered_len = filter.filteredScanlineLen(view) * view.layout.height;
    var out: std.Io.Writer.Allocating = try .initCapacity(allocator, filtered_len);
    errdefer out.deinit();

    try filter.writeFilteredNone(&out.writer, view);
    return try out.toOwnedSlice();
}

fn pngColorType(descriptor: ImageDescriptor) !u8 {
    return switch (descriptor.pixel_format) {
        .gray8 => 0,
        .rgb8 => 2,
        .rgba8 => 6,
    };
}
