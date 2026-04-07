const std = @import("std");
const types = @import("../../types.zig");
const view_mod = @import("../../view.zig");
const color = @import("color.zig");
const fdct = @import("fdct.zig");
const bit_writer = @import("bit_writer.zig");
const tables = @import("tables.zig");
const jpeg_types = @import("../../codecs/jpeg/types.zig");

pub const ImageU8 = types.ImageU8;
pub const ImageConstViewU8 = view_mod.ImageConstViewU8;

pub const JpegEncodeOptions = struct {
    quality: u8 = 90,
    exif_orientation: ?u8 = null,
};

pub const JpegEncodeError = types.ImageError || error{
    InvalidJpegQuality,
    UnsupportedJpegEncodeFormat,
};

const BitWriter = bit_writer.BitWriter;
const ComponentKind = color.ComponentKind;
const HuffmanCode = tables.HuffmanCode;
const zigzag = jpeg_types.zigzag;

const EntropyTables = struct {
    dc: [256]HuffmanCode,
    ac: [256]HuffmanCode,
};

pub fn encodeAlloc(allocator: std.mem.Allocator, image: *const ImageU8, options: JpegEncodeOptions) ![]u8 {
    const view = try view_mod.constViewFromImage(image);
    return encodeAllocView(allocator, view, options);
}

pub fn encodeAllocView(allocator: std.mem.Allocator, view: ImageConstViewU8, options: JpegEncodeOptions) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try writeView(allocator, &out.writer, view, options);
    return try out.toOwnedSlice();
}

pub fn write(allocator: std.mem.Allocator, writer: *std.Io.Writer, image: *const ImageU8, options: JpegEncodeOptions) !void {
    const view = try view_mod.constViewFromImage(image);
    try writeView(allocator, writer, view, options);
}

pub fn writeView(allocator: std.mem.Allocator, writer: *std.Io.Writer, view: ImageConstViewU8, options: JpegEncodeOptions) !void {
    try validateView(view, options);

    const color_image = view.layout.descriptor.pixel_format != .gray8;
    const quant_tables = try tables.buildScaledQuantTables(options.quality);
    const entropy_tables = EntropyTables{
        .dc = tables.buildCanonicalCodes(tables.dc_spec),
        .ac = tables.buildCanonicalCodes(tables.ac_spec),
    };

    const entropy = try encodeEntropy(allocator, view, quant_tables, entropy_tables);
    defer allocator.free(entropy);

    try writeMarker(writer, 0xD8);
    try writeJfifApp0(writer);
    if (options.exif_orientation) |orientation| try writeExifOrientationApp1(writer, orientation);
    try writeDqt(writer, 0, &quant_tables.luma);
    if (color_image) try writeDqt(writer, 1, &quant_tables.chroma);
    try writeSof0(writer, view.layout.width, view.layout.height, color_image);
    try writeDht(writer, 0, 0, tables.dc_spec);
    try writeDht(writer, 1, 0, tables.ac_spec);
    try writeSos(writer, color_image);
    try writer.writeAll(entropy);
    try writeMarker(writer, 0xD9);
}

pub fn writeFile(allocator: std.mem.Allocator, path: []const u8, image: *const ImageU8, options: JpegEncodeOptions) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var buffer: [16 * 1024]u8 = undefined;
    var file_writer = file.writer(&buffer);
    try write(allocator, &file_writer.interface, image, options);
    try file_writer.interface.flush();
}

fn validateView(view: ImageConstViewU8, options: JpegEncodeOptions) !void {
    try view.layout.descriptor.validate();
    if (options.quality == 0 or options.quality > 100) return error.InvalidJpegQuality;
    if (view.layout.width > std.math.maxInt(u16) or view.layout.height > std.math.maxInt(u16)) {
        return error.InvalidImageDimensions;
    }

    switch (view.layout.descriptor.pixel_format) {
        .gray8, .rgb8, .rgba8 => {},
    }
}

fn encodeEntropy(
    allocator: std.mem.Allocator,
    view: ImageConstViewU8,
    quant_tables: tables.QuantTables,
    entropy_tables: EntropyTables,
) ![]u8 {
    var bits = BitWriter{ .allocator = allocator };
    errdefer bits.deinit();

    const blocks_x = divCeil(view.layout.width, 8);
    const blocks_y = divCeil(view.layout.height, 8);
    var block: [64]f32 = undefined;
    var prev_dc = [_]i32{ 0, 0, 0 };

    if (view.layout.descriptor.pixel_format == .gray8) {
        for (0..blocks_y) |block_y| {
            for (0..blocks_x) |block_x| {
                color.fillBlock(view, .gray, block_x, block_y, &block);
                const coeffs = fdct.forwardQuantize(&block, &quant_tables.luma);
                try encodeBlock(&bits, &coeffs, &prev_dc[0], entropy_tables);
            }
        }
    } else {
        const components = [_]ComponentKind{ .y, .cb, .cr };
        const quantizers = [_]*const [64]u8{ &quant_tables.luma, &quant_tables.chroma, &quant_tables.chroma };

        for (0..blocks_y) |block_y| {
            for (0..blocks_x) |block_x| {
                for (components, quantizers, 0..) |component, quantizer, component_index| {
                    color.fillBlock(view, component, block_x, block_y, &block);
                    const coeffs = fdct.forwardQuantize(&block, quantizer);
                    try encodeBlock(&bits, &coeffs, &prev_dc[component_index], entropy_tables);
                }
            }
        }
    }

    try bits.flush();
    return try bits.toOwnedSlice();
}

fn encodeBlock(bits: *BitWriter, coeffs: *const [64]i32, prev_dc: *i32, entropy_tables: EntropyTables) !void {
    const dc_diff = coeffs[0] - prev_dc.*;
    prev_dc.* = coeffs[0];

    const dc_size = magnitudeCategory(dc_diff);
    if (!entropy_tables.dc[dc_size].valid) return error.UnsupportedJpegEncodeFormat;
    try writeCode(bits, entropy_tables.dc[dc_size]);
    if (dc_size > 0) try bits.writeBits(amplitudeBits(dc_diff, dc_size), dc_size);

    var zero_run: u8 = 0;
    for (1..64) |scan_index| {
        const coeff = coeffs[zigzag[scan_index]];
        if (coeff == 0) {
            zero_run += 1;
            continue;
        }

        while (zero_run >= 16) {
            try writeCode(bits, entropy_tables.ac[0xF0]);
            zero_run -= 16;
        }

        const ac_size = magnitudeCategory(coeff);
        const symbol = (@as(u8, zero_run) << 4) | ac_size;
        if (!entropy_tables.ac[symbol].valid) return error.UnsupportedJpegEncodeFormat;
        try writeCode(bits, entropy_tables.ac[symbol]);
        try bits.writeBits(amplitudeBits(coeff, ac_size), ac_size);
        zero_run = 0;
    }

    if (zero_run > 0) try writeCode(bits, entropy_tables.ac[0x00]);
}

fn writeCode(bits: *BitWriter, code: HuffmanCode) !void {
    if (!code.valid) return error.UnsupportedJpegEncodeFormat;
    try bits.writeBits(code.code, code.len);
}

fn magnitudeCategory(value: i32) u8 {
    if (value == 0) return 0;

    var abs_value: u32 = @intCast(if (value < 0) -value else value);
    var size: u8 = 0;
    while (abs_value > 0) : (abs_value >>= 1) size += 1;
    return size;
}

fn amplitudeBits(value: i32, size: u8) u16 {
    if (size == 0) return 0;
    if (value >= 0) return @intCast(value);

    const bias = (@as(i32, 1) << @intCast(size)) - 1;
    return @intCast(value + bias);
}

fn writeJfifApp0(writer: *std.Io.Writer) !void {
    try writeSegmentHeader(writer, 0xE0, 14);
    try writer.writeAll("JFIF\x00");
    try writer.writeByte(1);
    try writer.writeByte(1);
    try writer.writeByte(0);
    try writeU16(writer, 1);
    try writeU16(writer, 1);
    try writer.writeByte(0);
    try writer.writeByte(0);
}

fn writeExifOrientationApp1(writer: *std.Io.Writer, orientation: u8) !void {
    if (orientation < 1 or orientation > 8) return error.InvalidJpegQuality;

    try writeMarker(writer, 0xE1);
    try writeU16(writer, 34);
    try writer.writeAll("Exif\x00\x00");
    try writer.writeAll("II");
    try writer.writeByte(42);
    try writer.writeByte(0);
    try writer.writeAll(&[_]u8{ 8, 0, 0, 0 });
    try writer.writeAll(&[_]u8{ 1, 0 });
    try writer.writeAll(&[_]u8{ 0x12, 0x01 });
    try writer.writeAll(&[_]u8{ 3, 0 });
    try writer.writeAll(&[_]u8{ 1, 0, 0, 0 });
    try writer.writeByte(orientation);
    try writer.writeAll(&[_]u8{ 0, 0, 0 });
    try writer.writeAll(&[_]u8{ 0, 0, 0, 0 });
}

fn writeDqt(writer: *std.Io.Writer, table_id: u8, quant_table: *const [64]u8) !void {
    try writeSegmentHeader(writer, 0xDB, 65);
    try writer.writeByte(table_id);
    for (0..64) |i| {
        try writer.writeByte(quant_table[zigzag[i]]);
    }
}

fn writeSof0(writer: *std.Io.Writer, width: usize, height: usize, color_image: bool) !void {
    const component_count: u8 = if (color_image) 3 else 1;
    try writeSegmentHeader(writer, 0xC0, 6 + component_count * 3);
    try writer.writeByte(8);
    try writeU16(writer, height);
    try writeU16(writer, width);
    try writer.writeByte(component_count);

    try writer.writeByte(1);
    try writer.writeByte(0x11);
    try writer.writeByte(0);

    if (color_image) {
        try writer.writeByte(2);
        try writer.writeByte(0x11);
        try writer.writeByte(1);

        try writer.writeByte(3);
        try writer.writeByte(0x11);
        try writer.writeByte(1);
    }
}

fn writeDht(writer: *std.Io.Writer, class: u8, table_id: u8, spec: tables.HuffmanSpec) !void {
    try writeSegmentHeader(writer, 0xC4, 1 + spec.counts.len + spec.symbols.len);
    try writer.writeByte((class << 4) | table_id);
    try writer.writeAll(&spec.counts);
    try writer.writeAll(spec.symbols);
}

fn writeSos(writer: *std.Io.Writer, color_image: bool) !void {
    const component_count: u8 = if (color_image) 3 else 1;
    try writeSegmentHeader(writer, 0xDA, 1 + component_count * 2 + 3);
    try writer.writeByte(component_count);

    try writer.writeByte(1);
    try writer.writeByte(0x00);
    if (color_image) {
        try writer.writeByte(2);
        try writer.writeByte(0x00);
        try writer.writeByte(3);
        try writer.writeByte(0x00);
    }

    try writer.writeByte(0);
    try writer.writeByte(63);
    try writer.writeByte(0);
}

fn writeMarker(writer: *std.Io.Writer, marker: u8) !void {
    try writer.writeByte(0xFF);
    try writer.writeByte(marker);
}

fn writeSegmentHeader(writer: *std.Io.Writer, marker: u8, payload_len: usize) !void {
    try writeMarker(writer, marker);
    try writeU16(writer, payload_len + 2);
}

fn writeU16(writer: *std.Io.Writer, value: usize) !void {
    var buf: [2]u8 = undefined;
    std.mem.writeInt(u16, &buf, @intCast(value), .big);
    try writer.writeAll(&buf);
}

fn divCeil(value: usize, divisor: usize) usize {
    return (value + divisor - 1) / divisor;
}
