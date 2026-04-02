const std = @import("std");
const view_mod = @import("../../view.zig");

pub const ImageConstViewU8 = view_mod.ImageConstViewU8;

pub const FilterType = enum(u8) {
    none = 0,
    sub = 1,
    up = 2,
    average = 3,
    paeth = 4,
};

pub fn filteredScanlineLen(view: ImageConstViewU8) usize {
    return 1 + view.layout.width * view.layout.descriptor.bytesPerPixel();
}

pub fn buildAdaptiveFiltered(allocator: std.mem.Allocator, view: ImageConstViewU8) ![]u8 {
    const bytes_per_pixel = view.layout.descriptor.bytesPerPixel();
    const row_len = view.layout.width * bytes_per_pixel;
    const out_len = view.layout.height * (1 + row_len);
    const out = try allocator.alloc(u8, out_len);
    errdefer allocator.free(out);

    const scratch = try allocator.alloc(u8, row_len * 5);
    defer allocator.free(scratch);
    const rows = [5][]u8{
        scratch[0 * row_len .. 1 * row_len],
        scratch[1 * row_len .. 2 * row_len],
        scratch[2 * row_len .. 3 * row_len],
        scratch[3 * row_len .. 4 * row_len],
        scratch[4 * row_len .. 5 * row_len],
    };

    for (0..view.layout.height) |y| {
        const src_row = view.row(y);
        const prev_row = if (y == 0) null else view.row(y - 1);

        applyFilter(.none, rows[0], src_row, prev_row, bytes_per_pixel);
        applyFilter(.sub, rows[1], src_row, prev_row, bytes_per_pixel);
        applyFilter(.up, rows[2], src_row, prev_row, bytes_per_pixel);
        applyFilter(.average, rows[3], src_row, prev_row, bytes_per_pixel);
        applyFilter(.paeth, rows[4], src_row, prev_row, bytes_per_pixel);

        const best_index = chooseBestRow(rows);
        const dst_offset = y * (1 + row_len);
        out[dst_offset] = @intFromEnum(@as(FilterType, @enumFromInt(best_index)));
        @memcpy(out[dst_offset + 1 .. dst_offset + 1 + row_len], rows[best_index]);
    }

    return out;
}

fn chooseBestRow(rows: [5][]u8) usize {
    var best_index: usize = 0;
    var best_score = rowScore(rows[0]);
    for (rows[1..], 1..) |row, idx| {
        const score = rowScore(row);
        if (score < best_score) {
            best_score = score;
            best_index = idx;
        }
    }
    return best_index;
}

fn rowScore(row: []const u8) usize {
    var score: usize = 0;
    for (row) |byte| {
        const signed: i16 = if (byte < 128)
            @intCast(byte)
        else
            @as(i16, byte) - 256;
        score += @intCast(@abs(signed));
    }
    return score;
}

fn applyFilter(
    filter_type: FilterType,
    dst: []u8,
    src_row: []const u8,
    prev_row: ?[]const u8,
    bytes_per_pixel: usize,
) void {
    for (src_row, 0..) |value, i| {
        const left = if (i >= bytes_per_pixel) src_row[i - bytes_per_pixel] else 0;
        const up = if (prev_row) |row| row[i] else 0;
        const up_left = if (prev_row != null and i >= bytes_per_pixel) prev_row.?[i - bytes_per_pixel] else 0;

        dst[i] = switch (filter_type) {
            .none => value,
            .sub => value -% left,
            .up => value -% up,
            .average => value -% @as(u8, @intCast((@as(u16, left) + @as(u16, up)) / 2)),
            .paeth => value -% paeth(left, up, up_left),
        };
    }
}

fn paeth(a: u8, b: u8, c: u8) u8 {
    const p = @as(i32, a) + @as(i32, b) - @as(i32, c);
    const pa = @abs(p - @as(i32, a));
    const pb = @abs(p - @as(i32, b));
    const pc = @abs(p - @as(i32, c));
    if (pa <= pb and pa <= pc) return a;
    if (pb <= pc) return b;
    return c;
}
