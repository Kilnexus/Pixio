const std = @import("std");

const cos_table = buildCosTable();

pub fn forwardQuantize(input: *const [64]f32, quant: *const [64]u8) [64]i32 {
    var out = [_]i32{0} ** 64;

    for (0..8) |v| {
        for (0..8) |u| {
            var sum: f32 = 0.0;
            for (0..8) |y| {
                for (0..8) |x| {
                    sum += input[y * 8 + x] * cos_table[u][x] * cos_table[v][y];
                }
            }

            const coeff = 0.25 * alpha(u) * alpha(v) * sum;
            out[v * 8 + u] = @intFromFloat(@round(coeff / @as(f32, @floatFromInt(quant[v * 8 + u]))));
        }
    }

    return out;
}

fn alpha(index: usize) f32 {
    return if (index == 0) 0.70710677 else 1.0;
}

fn buildCosTable() [8][8]f32 {
    var table: [8][8]f32 = undefined;
    for (0..8) |freq| {
        for (0..8) |sample| {
            const angle = (@as(f64, @floatFromInt(2 * sample + 1)) * @as(f64, @floatFromInt(freq)) * std.math.pi) / 16.0;
            table[freq][sample] = @floatCast(std.math.cos(angle));
        }
    }
    return table;
}
