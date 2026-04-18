const std = @import("std");
const types = @import("../types.zig");

pub const ImageU8 = types.ImageU8;

pub const GifError = types.ImageError || error{
    InvalidGifHeader,
    InvalidGifBlock,
    InvalidGifData,
    InvalidGifDimensions,
    MissingGifImage,
    MissingGifColorTable,
    UnsupportedGifVariant,
    UnsupportedGifLzwCodeSize,
};

pub const AnimationFrame = struct {
    image: ImageU8,
    delay_cs: u16,

    pub fn deinit(self: *AnimationFrame) void {
        self.image.deinit();
        self.* = undefined;
    }
};

pub const Animation = struct {
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    channels: usize,
    loop_count: ?u16,
    frames: []AnimationFrame,

    pub fn deinit(self: *Animation) void {
        for (self.frames) |*frame| frame.deinit();
        self.allocator.free(self.frames);
        self.* = undefined;
    }
};

const MaxGifCode = 4096;

const GraphicControl = struct {
    transparent_index: ?u8 = null,
    delay_cs: u16 = 0,
    disposal_method: u3 = 0,
};

const BitReader = struct {
    bytes: []const u8,
    pos: usize = 0,
    bit_buffer: u32 = 0,
    bit_count: u8 = 0,

    fn readBits(self: *BitReader, count: u8) !u16 {
        while (self.bit_count < count) {
            if (self.pos >= self.bytes.len) return error.InvalidGifData;
            self.bit_buffer |= @as(u32, self.bytes[self.pos]) << @intCast(self.bit_count);
            self.bit_count += 8;
            self.pos += 1;
        }

        const mask: u32 = (@as(u32, 1) << @intCast(count)) - 1;
        const value: u16 = @intCast(self.bit_buffer & mask);
        self.bit_buffer >>= @intCast(count);
        self.bit_count -= count;
        return value;
    }
};

pub fn decodeRgb8(allocator: std.mem.Allocator, bytes: []const u8) !ImageU8 {
    return decodeWithChannels(allocator, bytes, 3);
}

pub fn decodeRgba8(allocator: std.mem.Allocator, bytes: []const u8) !ImageU8 {
    return decodeWithChannels(allocator, bytes, 4);
}

pub fn decodeFramesRgb8(allocator: std.mem.Allocator, bytes: []const u8) !Animation {
    return decodeFramesWithChannels(allocator, bytes, 3);
}

pub fn decodeFramesRgba8(allocator: std.mem.Allocator, bytes: []const u8) !Animation {
    return decodeFramesWithChannels(allocator, bytes, 4);
}

fn decodeWithChannels(allocator: std.mem.Allocator, bytes: []const u8, output_channels: usize) !ImageU8 {
    var animation = try decodeFramesWithChannels(allocator, bytes, output_channels);
    errdefer animation.deinit();
    if (animation.frames.len == 0) return error.MissingGifImage;

    const image = try cloneImage(allocator, &animation.frames[0].image);
    animation.deinit();
    return image;
}

fn decodeFramesWithChannels(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    output_channels: usize,
) !Animation {
    if (output_channels != 3 and output_channels != 4) return error.InvalidChannelCount;
    var header = try parseHeader(bytes);

    var canvas = try ImageU8.init(allocator, header.canvas_width, header.canvas_height, output_channels);
    errdefer canvas.deinit();
    if (output_channels == 3) {
        fillBackground(&canvas, header.global_color_table, header.background_index);
    } else {
        canvas.fill(0);
    }

    var frames = std.ArrayListUnmanaged(AnimationFrame).empty;
    errdefer {
        for (frames.items) |*frame| frame.deinit();
        frames.deinit(allocator);
    }

    var control = GraphicControl{};
    var loop_count: ?u16 = null;
    var saw_image = false;

    while (header.pos < bytes.len) {
        const sentinel = try readByte(bytes, &header.pos);
        switch (sentinel) {
            0x21 => {
                const label = try readByte(bytes, &header.pos);
                switch (label) {
                    0xF9 => control = try parseGraphicControl(bytes, &header.pos),
                    0xFF => {
                        if (try parseApplicationExtension(bytes, &header.pos)) |parsed_loop_count| {
                            loop_count = parsed_loop_count;
                        }
                    },
                    else => try skipSubBlocks(bytes, &header.pos),
                }
            },
            0x2C => {
                saw_image = true;
                var backup = if (control.disposal_method == 3)
                    try cloneImage(allocator, &canvas)
                else
                    null;
                defer if (backup) |*snapshot| snapshot.deinit();

                const rect = try parseImageDescriptor(allocator, bytes, &header.pos, &canvas, header.global_color_table, control);
                const frame_image = try cloneImage(allocator, &canvas);
                try frames.append(allocator, .{
                    .image = frame_image,
                    .delay_cs = control.delay_cs,
                });

                switch (control.disposal_method) {
                    2 => clearRectToBackground(&canvas, rect, header.global_color_table, header.background_index),
                    3 => if (backup) |snapshot| {
                        @memcpy(canvas.data, snapshot.data);
                    },
                    else => {},
                }
                control = .{};
            },
            0x3B => break,
            else => return error.InvalidGifBlock,
        }
    }

    if (!saw_image) return error.MissingGifImage;
    canvas.deinit();
    return .{
        .allocator = allocator,
        .width = header.canvas_width,
        .height = header.canvas_height,
        .channels = output_channels,
        .loop_count = loop_count,
        .frames = try frames.toOwnedSlice(allocator),
    };
}

fn fillBackground(image: *ImageU8, color_table: []const u8, background_index: u8) void {
    if (color_table.len == 0) {
        image.fill(0);
        return;
    }

    const idx = @as(usize, background_index) * 3;
    if (idx + 2 >= color_table.len) {
        image.fill(0);
        return;
    }

    for (0..image.height) |y| {
        for (0..image.width) |x| {
            const dst = image.pixelIndex(x, y, 0);
            image.data[dst] = color_table[idx];
            image.data[dst + 1] = color_table[idx + 1];
            image.data[dst + 2] = color_table[idx + 2];
        }
    }
}

fn parseGraphicControl(bytes: []const u8, pos: *usize) !GraphicControl {
    const block_size = try readByte(bytes, pos);
    if (block_size != 4) return error.InvalidGifBlock;
    const packed_fields = try readByte(bytes, pos);
    const delay_time: u16 = @intCast(try readU16le(bytes, pos));
    const transparent_index = try readByte(bytes, pos);
    const terminator = try readByte(bytes, pos);
    if (terminator != 0) return error.InvalidGifBlock;

    return .{
        .transparent_index = if ((packed_fields & 0x01) != 0) transparent_index else null,
        .delay_cs = delay_time,
        .disposal_method = @intCast((packed_fields >> 2) & 0x07),
    };
}

fn parseImageDescriptor(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    pos: *usize,
    image: *ImageU8,
    global_color_table: []const u8,
    control: GraphicControl,
) !ImageRect {
    const left = try readU16le(bytes, pos);
    const top = try readU16le(bytes, pos);
    const width = try readU16le(bytes, pos);
    const height = try readU16le(bytes, pos);
    if (width == 0 or height == 0) return error.InvalidGifDimensions;

    const packed_fields = try readByte(bytes, pos);
    const has_local_color_table = (packed_fields & 0x80) != 0;
    const interlaced = (packed_fields & 0x40) != 0;
    const local_color_table_size = if (has_local_color_table) @as(usize, 1) << @intCast((packed_fields & 0x07) + 1) else 0;

    var color_table = global_color_table;
    if (has_local_color_table) {
        const byte_len = local_color_table_size * 3;
        if (pos.* + byte_len > bytes.len) return error.InvalidGifData;
        color_table = bytes[pos.* .. pos.* + byte_len];
        pos.* += byte_len;
    }
    if (color_table.len == 0) return error.MissingGifColorTable;

    const min_code_size = try readByte(bytes, pos);
    if (min_code_size == 0 or min_code_size > 8) return error.UnsupportedGifLzwCodeSize;

    var compressed = std.ArrayListUnmanaged(u8).empty;
    defer compressed.deinit(allocator);
    try collectSubBlocks(allocator, bytes, pos, &compressed);

    const pixel_count = width * height;
    const indices = try decodeLzwIndices(allocator, compressed.items, min_code_size, pixel_count);
    defer allocator.free(indices);

    blitIndexedImage(image, color_table, indices, left, top, width, height, interlaced, control.transparent_index);
    return .{
        .left = left,
        .top = top,
        .width = width,
        .height = height,
    };
}

fn collectSubBlocks(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    pos: *usize,
    out: *std.ArrayListUnmanaged(u8),
) !void {
    while (true) {
        const block_len = try readByte(bytes, pos);
        if (block_len == 0) break;
        if (pos.* + block_len > bytes.len) return error.InvalidGifData;
        try out.appendSlice(allocator, bytes[pos.* .. pos.* + block_len]);
        pos.* += block_len;
    }
}

fn skipSubBlocks(bytes: []const u8, pos: *usize) !void {
    while (true) {
        const block_len = try readByte(bytes, pos);
        if (block_len == 0) break;
        if (pos.* + block_len > bytes.len) return error.InvalidGifData;
        pos.* += block_len;
    }
}

fn decodeLzwIndices(
    allocator: std.mem.Allocator,
    compressed: []const u8,
    min_code_size: u8,
    pixel_count: usize,
) ![]u8 {
    var output = try allocator.alloc(u8, pixel_count);
    errdefer allocator.free(output);

    const clear_code: u16 = @as(u16, 1) << @intCast(min_code_size);
    const end_code: u16 = clear_code + 1;

    var prefix = [_]u16{0} ** MaxGifCode;
    var suffix = [_]u8{0} ** MaxGifCode;
    var stack = [_]u8{0} ** MaxGifCode;
    for (0..clear_code) |i| {
        suffix[i] = @intCast(i);
    }

    var reader = BitReader{ .bytes = compressed };
    var code_size: u8 = min_code_size + 1;
    var next_code: u16 = end_code + 1;
    var old_code: ?u16 = null;
    var first_char: u8 = 0;
    var out_pos: usize = 0;

    while (out_pos < pixel_count) {
        const code = try reader.readBits(code_size);
        if (code == clear_code) {
            code_size = min_code_size + 1;
            next_code = end_code + 1;
            old_code = null;
            continue;
        }
        if (code == end_code) break;

        const in_code = code;
        var stack_len: usize = 0;
        var cur = code;

        if (old_code == null) {
            if (cur >= clear_code) return error.InvalidGifData;
        } else {
            if (cur > next_code) return error.InvalidGifData;
            if (cur == next_code) {
                stack[stack_len] = first_char;
                stack_len += 1;
                cur = old_code.?;
            }
        }

        while (cur >= clear_code) {
            if (cur >= next_code or stack_len >= stack.len) return error.InvalidGifData;
            stack[stack_len] = suffix[cur];
            stack_len += 1;
            cur = prefix[cur];
        }

        first_char = @intCast(cur);
        stack[stack_len] = first_char;
        stack_len += 1;

        while (stack_len > 0) {
            stack_len -= 1;
            if (out_pos >= pixel_count) break;
            output[out_pos] = stack[stack_len];
            out_pos += 1;
        }

        if (old_code != null and next_code < MaxGifCode) {
            prefix[next_code] = old_code.?;
            suffix[next_code] = first_char;
            next_code += 1;
            if (next_code == (@as(u16, 1) << @intCast(code_size)) and code_size < 12) {
                code_size += 1;
            }
        }

        old_code = in_code;
    }

    if (out_pos != pixel_count) return error.InvalidGifData;
    return output;
}

fn blitIndexedImage(
    image: *ImageU8,
    color_table: []const u8,
    indices: []const u8,
    left: usize,
    top: usize,
    width: usize,
    height: usize,
    interlaced: bool,
    transparent_index: ?u8,
) void {
    var src_index: usize = 0;
    if (interlaced) {
        const starts = [_]usize{ 0, 4, 2, 1 };
        const steps = [_]usize{ 8, 8, 4, 2 };
        for (starts, steps) |start, step| {
            var row = start;
            while (row < height and src_index < indices.len) : (row += step) {
                blitRow(image, color_table, indices, transparent_index, left, top, width, row, &src_index);
            }
        }
        return;
    }

    for (0..height) |row| {
        blitRow(image, color_table, indices, transparent_index, left, top, width, row, &src_index);
    }
}

fn clearRectToBackground(
    image: *ImageU8,
    rect: ImageRect,
    color_table: []const u8,
    background_index: u8,
) void {
    const fill = backgroundFill(color_table, background_index, image.channels);
    const max_y = @min(rect.top + rect.height, image.height);
    const max_x = @min(rect.left + rect.width, image.width);
    for (rect.top..max_y) |y| {
        for (rect.left..max_x) |x| {
            const dst = image.pixelIndex(x, y, 0);
            for (0..image.channels) |channel| {
                image.data[dst + channel] = fill[channel];
            }
        }
    }
}

fn backgroundFill(color_table: []const u8, background_index: u8, channels: usize) [4]u8 {
    var fill = [_]u8{ 0, 0, 0, 0 };
    if (channels == 4) return fill;
    if (color_table.len == 0) return fill;

    const idx = @as(usize, background_index) * 3;
    if (idx + 2 >= color_table.len) return fill;
    fill[0] = color_table[idx];
    fill[1] = color_table[idx + 1];
    fill[2] = color_table[idx + 2];
    if (channels == 4) fill[3] = 0xff;
    return fill;
}

fn cloneImage(allocator: std.mem.Allocator, source: *const ImageU8) !ImageU8 {
    var cloned = try ImageU8.init(allocator, source.width, source.height, source.channels);
    errdefer cloned.deinit();
    @memcpy(cloned.data, source.data);
    return cloned;
}

const ParsedHeader = struct {
    canvas_width: usize,
    canvas_height: usize,
    background_index: u8,
    global_color_table: []const u8,
    pos: usize,
};

const ImageRect = struct {
    left: usize,
    top: usize,
    width: usize,
    height: usize,
};

fn parseHeader(bytes: []const u8) !ParsedHeader {
    if (bytes.len < 13) return error.InvalidGifHeader;
    if (!std.mem.eql(u8, bytes[0..6], "GIF87a") and !std.mem.eql(u8, bytes[0..6], "GIF89a")) {
        return error.InvalidGifHeader;
    }

    var pos: usize = 6;
    const canvas_width = try readU16le(bytes, &pos);
    const canvas_height = try readU16le(bytes, &pos);
    if (canvas_width == 0 or canvas_height == 0) return error.InvalidGifDimensions;

    const packed_fields = try readByte(bytes, &pos);
    const has_global_color_table = (packed_fields & 0x80) != 0;
    const global_color_table_size = if (has_global_color_table) @as(usize, 1) << @intCast((packed_fields & 0x07) + 1) else 0;
    const background_index = try readByte(bytes, &pos);
    _ = try readByte(bytes, &pos);

    var global_color_table: []const u8 = &.{};
    if (has_global_color_table) {
        const byte_len = global_color_table_size * 3;
        if (pos + byte_len > bytes.len) return error.InvalidGifData;
        global_color_table = bytes[pos .. pos + byte_len];
        pos += byte_len;
    }

    return .{
        .canvas_width = canvas_width,
        .canvas_height = canvas_height,
        .background_index = background_index,
        .global_color_table = global_color_table,
        .pos = pos,
    };
}

fn parseApplicationExtension(bytes: []const u8, pos: *usize) !?u16 {
    const block_size = try readByte(bytes, pos);
    if (block_size != 11) {
        try skipFixedThenSubBlocks(bytes, pos, block_size);
        return null;
    }
    if (pos.* + block_size > bytes.len) return error.InvalidGifData;
    const app_id = bytes[pos.* .. pos.* + 8];
    const app_auth = bytes[pos.* + 8 .. pos.* + 11];
    pos.* += block_size;

    if (std.mem.eql(u8, app_id, "NETSCAPE") and std.mem.eql(u8, app_auth, "2.0")) {
        const sub_block_len = try readByte(bytes, pos);
        if (sub_block_len == 3 and pos.* + sub_block_len <= bytes.len and bytes[pos.*] == 1) {
            const loop_count = @as(u16, bytes[pos.* + 1]) | (@as(u16, bytes[pos.* + 2]) << 8);
            pos.* += sub_block_len;
            const terminator = try readByte(bytes, pos);
            if (terminator != 0) return error.InvalidGifBlock;
            return loop_count;
        }
        if (pos.* + sub_block_len > bytes.len) return error.InvalidGifData;
        pos.* += sub_block_len;
        try skipSubBlocks(bytes, pos);
        return null;
    }

    try skipSubBlocks(bytes, pos);
    return null;
}

fn skipFixedThenSubBlocks(bytes: []const u8, pos: *usize, block_size: u8) !void {
    if (pos.* + block_size > bytes.len) return error.InvalidGifData;
    pos.* += block_size;
    try skipSubBlocks(bytes, pos);
}

fn blitRow(
    image: *ImageU8,
    color_table: []const u8,
    indices: []const u8,
    transparent_index: ?u8,
    left: usize,
    top: usize,
    width: usize,
    row: usize,
    src_index: *usize,
) void {
    const dst_y = top + row;
    for (0..width) |x| {
        if (src_index.* >= indices.len) return;
        const palette_index = indices[src_index.*];
        src_index.* += 1;

        if (transparent_index != null and palette_index == transparent_index.?) continue;

        const dst_x = left + x;
        if (dst_x >= image.width or dst_y >= image.height) continue;

        const color_offset = @as(usize, palette_index) * 3;
        if (color_offset + 2 >= color_table.len) continue;

        const dst = image.pixelIndex(dst_x, dst_y, 0);
        image.data[dst] = color_table[color_offset];
        image.data[dst + 1] = color_table[color_offset + 1];
        image.data[dst + 2] = color_table[color_offset + 2];
        if (image.channels == 4) image.data[dst + 3] = 0xff;
    }
}

fn readByte(bytes: []const u8, pos: *usize) !u8 {
    if (pos.* >= bytes.len) return error.InvalidGifData;
    const value = bytes[pos.*];
    pos.* += 1;
    return value;
}

fn readU16le(bytes: []const u8, pos: *usize) !usize {
    if (pos.* + 2 > bytes.len) return error.InvalidGifData;
    const lo = bytes[pos.*];
    const hi = bytes[pos.* + 1];
    pos.* += 2;
    return @as(usize, lo) | (@as(usize, hi) << 8);
}

test "gif multi-frame decoder returns composited frames in order" {
    const testing = std.testing;

    const gif_bytes = [_]u8{
        'G',  'I',  'F',  '8',  '9',  'a',
        0x01, 0x00, 0x01, 0x00, 0x80, 0x00,
        0x00, 0xff, 0x00, 0x00, 0x00, 0xff,
        0x00, 0x21, 0xf9, 0x04, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x2c, 0x00, 0x00,
        0x00, 0x00, 0x01, 0x00, 0x01, 0x00,
        0x00, 0x02, 0x02, 0x44, 0x01, 0x00,
        0x21, 0xf9, 0x04, 0x00, 0x02, 0x00,
        0x00, 0x00, 0x2c, 0x00, 0x00, 0x00,
        0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
        0x02, 0x02, 0x4c, 0x01, 0x00, 0x3b,
    };

    var animation = try decodeFramesRgb8(testing.allocator, &gif_bytes);
    defer animation.deinit();

    try testing.expectEqual(@as(usize, 1), animation.width);
    try testing.expectEqual(@as(usize, 1), animation.height);
    try testing.expectEqual(@as(usize, 2), animation.frames.len);
    try testing.expectEqual(@as(u16, 1), animation.frames[0].delay_cs);
    try testing.expectEqual(@as(u16, 2), animation.frames[1].delay_cs);
    try testing.expectEqual(@as(u8, 0xff), animation.frames[0].image.data[0]);
    try testing.expectEqual(@as(u8, 0x00), animation.frames[0].image.data[1]);
    try testing.expectEqual(@as(u8, 0x00), animation.frames[0].image.data[2]);
    try testing.expectEqual(@as(u8, 0x00), animation.frames[1].image.data[0]);
    try testing.expectEqual(@as(u8, 0xff), animation.frames[1].image.data[1]);
    try testing.expectEqual(@as(u8, 0x00), animation.frames[1].image.data[2]);
}
