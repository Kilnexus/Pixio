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
pub const PngTextEntry = struct {
    keyword: []const u8,
    text: []const u8,
};

pub const PngEncodeOptions = struct {
    text_entries: []const PngTextEntry = &.{},
};

pub const PngEncodeError = types.ImageError || error{
    UnsupportedPngEncodeFormat,
    InvalidPngTextEntry,
};

pub fn encodeAlloc(allocator: std.mem.Allocator, image: *const ImageU8) ![]u8 {
    return encodeAllocWithOptions(allocator, image, .{});
}

pub fn encodeAllocWithOptions(allocator: std.mem.Allocator, image: *const ImageU8, options: PngEncodeOptions) ![]u8 {
    const view = try view_mod.constViewFromImage(image);
    return encodeAllocView(allocator, view, options);
}

pub fn encodeAllocView(allocator: std.mem.Allocator, view: ImageConstViewU8, options: PngEncodeOptions) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try writeView(allocator, &out.writer, view, options);
    return try out.toOwnedSlice();
}

pub fn write(allocator: std.mem.Allocator, writer: *std.Io.Writer, image: *const ImageU8) !void {
    return writeWithOptions(allocator, writer, image, .{});
}

pub fn writeWithOptions(allocator: std.mem.Allocator, writer: *std.Io.Writer, image: *const ImageU8, options: PngEncodeOptions) !void {
    const view = try view_mod.constViewFromImage(image);
    try writeView(allocator, writer, view, options);
}

pub fn writeView(allocator: std.mem.Allocator, writer: *std.Io.Writer, view: ImageConstViewU8, options: PngEncodeOptions) !void {
    try view.layout.descriptor.validate();
    const color_type = try pngColorType(view.layout.descriptor);

    try container.writeSignature(writer);
    try container.writeIhdr(writer, view.layout.width, view.layout.height, 8, color_type);
    try writeTextChunks(allocator, writer, options.text_entries);

    const filtered = try buildFilteredScanlines(allocator, view);
    defer allocator.free(filtered);

    const idat = try zlib.encodeStoredAlloc(allocator, filtered);
    defer allocator.free(idat);

    try container.writeChunk(writer, .{ 'I', 'D', 'A', 'T' }, idat);
    try container.writeIend(writer);
}

pub fn writeFile(allocator: std.mem.Allocator, path: []const u8, image: *const ImageU8) !void {
    return writeFileWithOptions(allocator, path, image, .{});
}

pub fn writeFileWithOptions(allocator: std.mem.Allocator, path: []const u8, image: *const ImageU8, options: PngEncodeOptions) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var buffer: [16 * 1024]u8 = undefined;
    var file_writer = file.writer(&buffer);
    try writeWithOptions(allocator, &file_writer.interface, image, options);
    try file_writer.interface.flush();
}

fn buildFilteredScanlines(allocator: std.mem.Allocator, view: ImageConstViewU8) ![]u8 {
    return filter.buildAdaptiveFiltered(allocator, view);
}

fn pngColorType(descriptor: ImageDescriptor) !u8 {
    return switch (descriptor.pixel_format) {
        .gray8 => 0,
        .rgb8 => 2,
        .rgba8 => 6,
    };
}

fn writeTextChunks(allocator: std.mem.Allocator, writer: *std.Io.Writer, entries: []const PngTextEntry) !void {
    for (entries) |entry| {
        try validateTextEntry(entry);
        const payload_len = entry.keyword.len + 1 + entry.text.len;
        const payload = try allocator.alloc(u8, payload_len);
        defer allocator.free(payload);
        @memcpy(payload[0..entry.keyword.len], entry.keyword);
        payload[entry.keyword.len] = 0;
        @memcpy(payload[entry.keyword.len + 1 ..], entry.text);
        try container.writeChunk(writer, .{ 't', 'E', 'X', 't' }, payload);
    }
}

fn validateTextEntry(entry: PngTextEntry) !void {
    if (entry.keyword.len == 0 or entry.keyword.len > 79) return error.InvalidPngTextEntry;
    if (std.mem.indexOfScalar(u8, entry.keyword, 0) != null) return error.InvalidPngTextEntry;
    if (std.mem.indexOfScalar(u8, entry.text, 0) != null) return error.InvalidPngTextEntry;
}
