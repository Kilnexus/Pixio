const std = @import("std");
const format = @import("format.zig");
const png = @import("codecs/png.zig");
const bmp = @import("codecs/bmp.zig");
const jpeg = @import("codecs/jpeg.zig");
const gif = @import("codecs/gif.zig");
const ico = @import("codecs/ico.zig");
const webp = @import("codecs/webp.zig");
const webp_probe = @import("codecs/webp/probe.zig");
const webp_container = @import("codecs/webp/container.zig");

pub const ImageFormat = format.ImageFormat;

pub const ImageInfo = struct {
    format: ImageFormat,
    width: usize,
    height: usize,
    channels: usize,
    has_alpha: bool,
};

pub const WebpInfo = webp.WebpInfo;
pub const WebpChunkTag = webp.WebpChunkTag;
pub const Vp8lStreamInfo = webp.Vp8lStreamInfo;
pub const Vp8lTransformType = webp.Vp8lTransformType;
pub const Vp8lImageRole = webp.Vp8lImageRole;
pub const Vp8lImageDataHeader = webp.Vp8lImageDataHeader;
pub const Vp8lPrefixCodeKind = webp.Vp8lPrefixCodeKind;
pub const Vp8lSimplePrefixCode = webp.Vp8lSimplePrefixCode;
pub const Vp8lNormalPrefixCode = webp.Vp8lNormalPrefixCode;
pub const Vp8lCanonicalCodeEntry = webp.Vp8lCanonicalCodeEntry;
pub const Vp8lCanonicalPrefixSummary = webp.Vp8lCanonicalPrefixSummary;
pub const Vp8lCanonicalSymbolStream = webp.Vp8lCanonicalSymbolStream;
pub const Vp8lPrefixCodeGroupDetail = webp.Vp8lPrefixCodeGroupDetail;
pub const Vp8lEventKind = webp.Vp8lEventKind;
pub const Vp8lEvent = webp.Vp8lEvent;
pub const Vp8lEventStream = webp.Vp8lEventStream;
pub const Vp8lArgbImage = webp.Vp8lArgbImage;
pub const Vp8lPrefixCodeHeader = webp.Vp8lPrefixCodeHeader;
pub const Vp8lPrefixCodeGroup = webp.Vp8lPrefixCodeGroup;
pub const Vp8lEntropyImageDataHeader = webp.Vp8lEntropyImageDataHeader;

pub const ProbeError =
    png.PngError ||
    bmp.BmpError ||
    jpeg.JpegError ||
    gif.GifError ||
    ico.IcoError ||
    webp.WebpError ||
    error{
        UnsupportedImageFormat,
        FileTooBig,
    };

pub fn probeInfo(bytes: []const u8) !ImageInfo {
    return switch (format.detectFormat(bytes)) {
        .png => try probePng(bytes),
        .bmp => try probeBmp(bytes),
        .jpeg => try probeJpeg(bytes),
        .gif => try probeGif(bytes),
        .ico => try probeIco(bytes),
        .webp => try probeWebp(bytes),
        else => error.UnsupportedImageFormat,
    };
}

pub fn probeFileInfo(allocator: std.mem.Allocator, path: []const u8) !ImageInfo {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var header: [64]u8 = undefined;
    const header_len = try file.preadAll(&header, 0);
    const bytes = header[0..header_len];

    return switch (format.detectFormat(bytes)) {
        .png => try probePngFile(file),
        .bmp => try probeBmp(bytes),
        .jpeg => try probeJpegFile(file),
        .gif => try probeGif(bytes),
        .ico => try probeIcoFile(allocator, file),
        .webp => try probeWebpImageFile(file),
        else => error.UnsupportedImageFormat,
    };
}

pub fn probeWebpInfo(bytes: []const u8) !WebpInfo {
    if (format.detectFormat(bytes) != .webp) return error.UnsupportedImageFormat;
    return webp.probeInfo(bytes);
}

pub fn probeWebpFileInfo(allocator: std.mem.Allocator, path: []const u8) !WebpInfo {
    _ = allocator;

    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return probeWebpFile(file);
}

pub fn probeWebpPrimaryChunkTag(bytes: []const u8) !WebpChunkTag {
    if (format.detectFormat(bytes) != .webp) return error.UnsupportedImageFormat;
    return (try webp.findPrimaryChunk(bytes)).tag;
}

pub fn inspectWebpVp8l(bytes: []const u8) !Vp8lStreamInfo {
    if (format.detectFormat(bytes) != .webp) return error.UnsupportedImageFormat;
    return webp.inspectVp8l(bytes);
}

pub fn inspectVp8lImageDataAtBitPos(
    payload: []const u8,
    start_bit_pos: usize,
    width: usize,
    height: usize,
    role: Vp8lImageRole,
) !Vp8lImageDataHeader {
    return webp.inspectVp8lImageDataAtBitPos(payload, start_bit_pos, width, height, role);
}

pub fn inspectVp8lNormalPrefixCodeAtBitPos(
    payload: []const u8,
    start_bit_pos: usize,
    alphabet_size: usize,
) !Vp8lNormalPrefixCode {
    return webp.inspectVp8lNormalPrefixCodeAtBitPos(payload, start_bit_pos, alphabet_size);
}

pub fn inspectVp8lCanonicalSymbolStreamAtBitPos(
    payload: []const u8,
    start_bit_pos: usize,
    code_lengths: []const u8,
    symbol_count: usize,
) !Vp8lCanonicalSymbolStream {
    return webp.inspectVp8lCanonicalSymbolStreamAtBitPos(payload, start_bit_pos, code_lengths, symbol_count);
}

pub fn inspectVp8lPrefixCodeGroupAtBitPos(
    payload: []const u8,
    start_bit_pos: usize,
    alphabet_sizes: [5]usize,
) !Vp8lPrefixCodeGroupDetail {
    return webp.inspectVp8lPrefixCodeGroupAtBitPos(payload, start_bit_pos, alphabet_sizes);
}

pub fn inspectVp8lEventStreamAtBitPos(
    payload: []const u8,
    prefix_group_start_bit_pos: usize,
    alphabet_sizes: [5]usize,
    width: usize,
    height: usize,
    color_cache_bits: usize,
    max_events: usize,
) !Vp8lEventStream {
    return webp.inspectVp8lEventStreamAtBitPos(
        payload,
        prefix_group_start_bit_pos,
        alphabet_sizes,
        width,
        height,
        color_cache_bits,
        max_events,
    );
}

pub fn resolveMetaPrefixCode(
    entropy_image: ?[]const u32,
    prefix_bits: usize,
    prefix_image_width: usize,
    x: usize,
    y: usize,
) !usize {
    return webp.resolveMetaPrefixCode(entropy_image, prefix_bits, prefix_image_width, x, y);
}

pub fn decodeVp8lSingleGroupArgbAtBitPos(
    allocator: std.mem.Allocator,
    payload: []const u8,
    prefix_group_start_bit_pos: usize,
    alphabet_sizes: [5]usize,
    width: usize,
    height: usize,
    color_cache_bits: usize,
) !Vp8lArgbImage {
    return webp.decodeVp8lSingleGroupArgbAtBitPos(
        allocator,
        payload,
        prefix_group_start_bit_pos,
        alphabet_sizes,
        width,
        height,
        color_cache_bits,
    );
}

pub fn decodeVp8lPayloadArgb(allocator: std.mem.Allocator, payload: []const u8) !Vp8lArgbImage {
    return webp.decodeVp8lPayloadArgb(allocator, payload);
}

fn probePng(bytes: []const u8) !ImageInfo {
    if (bytes.len < 33) return error.InvalidPngChunk;
    if (readU32be(bytes[8..12]) != 13) return error.InvalidPngChunk;
    if (!std.mem.eql(u8, bytes[12..16], "IHDR")) return error.MissingPngIhdr;

    const width = readU32be(bytes[16..20]);
    const height = readU32be(bytes[20..24]);
    if (width == 0 or height == 0) return error.InvalidPngDimensions;
    const color_type = bytes[25];
    var has_alpha = color_type == 4 or color_type == 6;

    var offset: usize = 33;
    while (offset + 12 <= bytes.len) {
        const chunk_len = readU32be(bytes[offset .. offset + 4]);
        const chunk_type = bytes[offset + 4 .. offset + 8];
        offset += 8;
        if (offset + chunk_len + 4 > bytes.len) return error.InvalidPngChunk;

        if (std.mem.eql(u8, chunk_type, "tRNS")) {
            if (pngChunkHasTransparency(color_type, bytes[offset .. offset + chunk_len])) has_alpha = true;
        } else if (std.mem.eql(u8, chunk_type, "IDAT") or std.mem.eql(u8, chunk_type, "IEND")) {
            break;
        }

        offset += chunk_len + 4;
    }

    return .{
        .format = .png,
        .width = width,
        .height = height,
        .channels = 3,
        .has_alpha = has_alpha,
    };
}

fn probeBmp(bytes: []const u8) !ImageInfo {
    if (bytes.len < 30) return error.InvalidBmpHeader;

    const width_i = readI32le(bytes[18..22]);
    const height_i = readI32le(bytes[22..26]);
    if (width_i == 0 or height_i == 0) return error.InvalidBmpDimensions;
    const bit_count = readU16le(bytes[28..30]);
    return .{
        .format = .bmp,
        .width = @intCast(@abs(width_i)),
        .height = @intCast(@abs(height_i)),
        .channels = 3,
        .has_alpha = bit_count == 32,
    };
}

fn probeGif(bytes: []const u8) !ImageInfo {
    if (bytes.len < 10) return error.InvalidGifHeader;

    const width = readU16le(bytes[6..8]);
    const height = readU16le(bytes[8..10]);
    if (width == 0 or height == 0) return error.InvalidGifDimensions;

    return .{
        .format = .gif,
        .width = width,
        .height = height,
        .channels = 3,
        .has_alpha = false,
    };
}

fn probeIco(bytes: []const u8) !ImageInfo {
    if (bytes.len < 6) return error.InvalidIcoHeader;

    const count = readU16le(bytes[4..6]);
    if (count == 0) return error.InvalidIcoDirectory;
    if (bytes.len < 6 + count * 16) return error.InvalidIcoDirectory;

    var best_width: usize = 0;
    var best_height: usize = 0;
    var best_score: usize = 0;
    var best_alpha = false;

    for (0..count) |i| {
        const offset = 6 + i * 16;
        const width = if (bytes[offset] == 0) @as(usize, 256) else bytes[offset];
        const height = if (bytes[offset + 1] == 0) @as(usize, 256) else bytes[offset + 1];
        const bit_count = readU16le(bytes[offset + 6 .. offset + 8]);
        const score = width * height * @max(bit_count, 1);
        if (score > best_score) {
            best_score = score;
            best_width = width;
            best_height = height;
            best_alpha = bit_count == 32;
        }
    }

    if (best_score == 0) return error.MissingIcoImage;

    return .{
        .format = .ico,
        .width = best_width,
        .height = best_height,
        .channels = 3,
        .has_alpha = best_alpha,
    };
}

fn probeJpeg(bytes: []const u8) !ImageInfo {
    if (bytes.len < 4 or bytes[0] != 0xff or bytes[1] != 0xd8) return error.InvalidJpegHeader;

    var pos: usize = 2;
    while (pos + 1 < bytes.len) {
        while (pos < bytes.len and bytes[pos] != 0xff) : (pos += 1) {}
        if (pos + 1 >= bytes.len) break;
        while (pos < bytes.len and bytes[pos] == 0xff) : (pos += 1) {}
        if (pos >= bytes.len) break;

        const marker = bytes[pos];
        pos += 1;

        if (marker == 0xd9 or marker == 0xda) break;
        if (marker >= 0xd0 and marker <= 0xd7) continue;
        if (pos + 2 > bytes.len) return error.InvalidJpegData;
        const seg_len = readU16be(bytes[pos .. pos + 2]);
        if (seg_len < 2 or pos + seg_len > bytes.len) return error.InvalidJpegSegment;

        if ((marker >= 0xc0 and marker <= 0xc3) or (marker >= 0xc5 and marker <= 0xc7) or (marker >= 0xc9 and marker <= 0xcb) or (marker >= 0xcd and marker <= 0xcf)) {
            if (seg_len < 8) return error.InvalidJpegSegment;
            const height = readU16be(bytes[pos + 3 .. pos + 5]);
            const width = readU16be(bytes[pos + 5 .. pos + 7]);
            const components = bytes[pos + 7];
            return .{
                .format = .jpeg,
                .width = width,
                .height = height,
                .channels = if (components == 1) 1 else 3,
                .has_alpha = false,
            };
        }

        pos += seg_len;
    }

    return error.MissingJpegFrame;
}

fn probeWebp(bytes: []const u8) !ImageInfo {
    const info = try webp.probeInfo(bytes);
    return .{
        .format = .webp,
        .width = info.width,
        .height = info.height,
        .channels = 3,
        .has_alpha = info.has_alpha,
    };
}

fn probePngFile(file: std.fs.File) !ImageInfo {
    var header: [33]u8 = undefined;
    if (try file.preadAll(&header, 0) < header.len) return error.InvalidPngChunk;
    if (readU32be(header[8..12]) != 13) return error.InvalidPngChunk;
    if (!std.mem.eql(u8, header[12..16], "IHDR")) return error.MissingPngIhdr;

    const width = readU32be(header[16..20]);
    const height = readU32be(header[20..24]);
    if (width == 0 or height == 0) return error.InvalidPngDimensions;
    const color_type = header[25];
    var has_alpha = color_type == 4 or color_type == 6;

    const stat = try file.stat();
    if (stat.size > std.math.maxInt(usize)) return error.FileTooBig;
    const file_size: usize = @intCast(stat.size);

    var offset: usize = 33;
    var chunk_header: [8]u8 = undefined;
    var trns_buf: [256]u8 = undefined;
    while (offset + 12 <= file_size) {
        if (try file.preadAll(&chunk_header, offset) < chunk_header.len) return error.InvalidPngChunk;
        const chunk_len = readU32be(chunk_header[0..4]);
        const chunk_type = chunk_header[4..8];
        offset += 8;
        if (offset + chunk_len + 4 > file_size) return error.InvalidPngChunk;

        if (std.mem.eql(u8, chunk_type, "tRNS")) {
            if (chunk_len > trns_buf.len) return error.InvalidPngChunk;
            if (try file.preadAll(trns_buf[0..chunk_len], offset) < chunk_len) return error.InvalidPngChunk;
            if (pngChunkHasTransparency(color_type, trns_buf[0..chunk_len])) has_alpha = true;
        } else if (std.mem.eql(u8, chunk_type, "IDAT") or std.mem.eql(u8, chunk_type, "IEND")) {
            break;
        }

        offset += chunk_len + 4;
    }

    return .{
        .format = .png,
        .width = width,
        .height = height,
        .channels = 3,
        .has_alpha = has_alpha,
    };
}

fn probeIcoFile(allocator: std.mem.Allocator, file: std.fs.File) !ImageInfo {
    const stat = try file.stat();
    if (stat.size > std.math.maxInt(usize)) return error.FileTooBig;
    const file_size: usize = @intCast(stat.size);

    var header: [6]u8 = undefined;
    const header_len = try file.preadAll(&header, 0);
    if (header_len < header.len) return error.InvalidIcoHeader;

    const count = readU16le(header[4..6]);
    if (count == 0) return error.InvalidIcoDirectory;

    const directory_len = 6 + count * 16;
    if (directory_len > file_size) return error.InvalidIcoDirectory;

    const directory = try allocator.alloc(u8, directory_len);
    defer allocator.free(directory);

    const directory_read = try file.preadAll(directory, 0);
    if (directory_read < directory_len) return error.InvalidIcoDirectory;

    return probeIco(directory);
}

fn probeJpegFile(file: std.fs.File) !ImageInfo {
    var soi: [2]u8 = undefined;
    const soi_len = try file.preadAll(&soi, 0);
    if (soi_len < soi.len or soi[0] != 0xff or soi[1] != 0xd8) return error.InvalidJpegHeader;

    var pos: u64 = 2;
    while (true) {
        while (true) {
            const byte = try readByteAt(file, pos) orelse return error.MissingJpegFrame;
            if (byte == 0xff) break;
            pos += 1;
        }

        var marker: u8 = 0;
        while (true) {
            pos += 1;
            marker = try readByteAt(file, pos) orelse return error.InvalidJpegMarker;
            if (marker != 0xff) {
                pos += 1;
                break;
            }
        }

        if (marker == 0xd9 or marker == 0xda) break;
        if (marker >= 0xd0 and marker <= 0xd7) continue;

        var segment_len_bytes: [2]u8 = undefined;
        if (try file.preadAll(&segment_len_bytes, pos) < segment_len_bytes.len) return error.InvalidJpegData;
        const segment_len = readU16be(segment_len_bytes[0..2]);
        if (segment_len < 2) return error.InvalidJpegSegment;

        if (isJpegFrameMarker(marker)) {
            if (segment_len < 8) return error.InvalidJpegSegment;

            var frame_header: [6]u8 = undefined;
            if (try file.preadAll(&frame_header, pos + 2) < frame_header.len) return error.InvalidJpegSegment;

            const height = readU16be(frame_header[1..3]);
            const width = readU16be(frame_header[3..5]);
            const components = frame_header[5];
            return .{
                .format = .jpeg,
                .width = width,
                .height = height,
                .channels = if (components == 1) 1 else 3,
                .has_alpha = false,
            };
        }

        pos += segment_len;
    }

    return error.MissingJpegFrame;
}

fn probeWebpFile(file: std.fs.File) !WebpInfo {
    const stat = try file.stat();
    if (stat.size > std.math.maxInt(usize)) return error.FileTooBig;
    const file_size: usize = @intCast(stat.size);

    var header: [12]u8 = undefined;
    const header_len = try file.preadAll(&header, 0);
    if (header_len < header.len) return error.InvalidWebpHeader;
    try webp_container.validateHeader(&header);

    var vp8x_info: ?WebpInfo = null;
    var primary_info: ?WebpInfo = null;
    var saw_animation_chunk = false;
    var offset: usize = 12;

    while (offset + 8 <= file_size) {
        var chunk_header: [8]u8 = undefined;
        if (try file.preadAll(&chunk_header, offset) < chunk_header.len) return error.InvalidWebpChunk;

        const chunk_size = webp_container.readU32le(chunk_header[4..8]);
        const payload_offset = offset + 8;
        if (payload_offset > file_size or chunk_size > file_size - payload_offset) return error.InvalidWebpChunk;

        switch (webp_container.mapChunkTag(chunk_header[0..4])) {
            .vp8x => {
                var payload: [10]u8 = undefined;
                const payload_len = @min(payload.len, chunk_size);
                if (try file.preadAll(payload[0..payload_len], payload_offset) < payload_len) return error.InvalidWebpChunk;
                vp8x_info = try webp_probe.parseVp8x(payload[0..payload_len]);
            },
            .vp8 => {
                var payload: [10]u8 = undefined;
                const payload_len = @min(payload.len, chunk_size);
                if (try file.preadAll(payload[0..payload_len], payload_offset) < payload_len) return error.InvalidWebpChunk;
                primary_info = try webp_probe.parseVp8(payload[0..payload_len]);
            },
            .vp8l => {
                var payload: [5]u8 = undefined;
                const payload_len = @min(payload.len, chunk_size);
                if (try file.preadAll(payload[0..payload_len], payload_offset) < payload_len) return error.InvalidWebpChunk;
                primary_info = try webp_probe.parseVp8l(payload[0..payload_len]);
            },
            .anmf => saw_animation_chunk = true,
            else => {},
        }

        const payload_end = payload_offset + chunk_size;
        offset = payload_end + (chunk_size & 1);
    }

    if (primary_info) |info| {
        var resolved = info;
        if (vp8x_info) |extended| {
            resolved.has_alpha = extended.has_alpha;
            resolved.is_animated = extended.is_animated;
            resolved.has_icc = extended.has_icc;
            resolved.has_exif = extended.has_exif;
            resolved.has_xmp = extended.has_xmp;
            resolved.width = extended.width;
            resolved.height = extended.height;
        }
        return resolved;
    }

    if (vp8x_info) |extended| {
        if (extended.is_animated and saw_animation_chunk) return extended;
    }

    return error.MissingWebpChunk;
}

fn probeWebpImageFile(file: std.fs.File) !ImageInfo {
    const info = try probeWebpFile(file);
    return .{
        .format = .webp,
        .width = info.width,
        .height = info.height,
        .channels = 3,
        .has_alpha = info.has_alpha,
    };
}

fn readByteAt(file: std.fs.File, offset: u64) !?u8 {
    var byte: [1]u8 = undefined;
    const read = try file.preadAll(&byte, offset);
    if (read == 0) return null;
    return byte[0];
}

fn isJpegFrameMarker(marker: u8) bool {
    return (marker >= 0xc0 and marker <= 0xc3) or
        (marker >= 0xc5 and marker <= 0xc7) or
        (marker >= 0xc9 and marker <= 0xcb) or
        (marker >= 0xcd and marker <= 0xcf);
}

fn pngChunkHasTransparency(color_type: u8, chunk_data: []const u8) bool {
    return switch (color_type) {
        0 => chunk_data.len == 2,
        2 => chunk_data.len == 6,
        3 => blk: {
            for (chunk_data) |alpha| {
                if (alpha != 0xff) break :blk true;
            }
            break :blk false;
        },
        else => false,
    };
}

fn readU16le(bytes: []const u8) usize {
    return @as(usize, bytes[0]) | (@as(usize, bytes[1]) << 8);
}

fn readU16be(bytes: []const u8) usize {
    return (@as(usize, bytes[0]) << 8) | @as(usize, bytes[1]);
}

fn readU32be(bytes: []const u8) usize {
    return (@as(usize, bytes[0]) << 24) |
        (@as(usize, bytes[1]) << 16) |
        (@as(usize, bytes[2]) << 8) |
        @as(usize, bytes[3]);
}

fn readI32le(bytes: []const u8) i32 {
    return @bitCast(@as(u32, @intCast(
        @as(u32, bytes[0]) |
            (@as(u32, bytes[1]) << 8) |
            (@as(u32, bytes[2]) << 16) |
            (@as(u32, bytes[3]) << 24),
    )));
}
