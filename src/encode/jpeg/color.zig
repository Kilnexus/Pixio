const std = @import("std");
const view_mod = @import("../../view.zig");

pub const ImageConstViewU8 = view_mod.ImageConstViewU8;

pub const ComponentKind = enum {
    gray,
    y,
    cb,
    cr,
};

pub fn fillBlock(view: ImageConstViewU8, component: ComponentKind, block_x: usize, block_y: usize, out: *[64]f32) void {
    std.debug.assert(view.layout.width > 0);
    std.debug.assert(view.layout.height > 0);

    const start_x = block_x * 8;
    const start_y = block_y * 8;
    for (0..8) |dy| {
        for (0..8) |dx| {
            const x = @min(start_x + dx, view.layout.width - 1);
            const y = @min(start_y + dy, view.layout.height - 1);
            out[dy * 8 + dx] = sampleComponent(view, component, x, y);
        }
    }
}

fn sampleComponent(view: ImageConstViewU8, component: ComponentKind, x: usize, y: usize) f32 {
    const pixel = view.pixelSlice(x, y);
    return switch (view.layout.descriptor.pixel_format) {
        .gray8 => {
            const value = @as(f32, @floatFromInt(pixel[0]));
            return switch (component) {
                .gray, .y => value - 128.0,
                .cb, .cr => 0.0,
            };
        },
        .rgb8, .rgba8 => {
            const r = @as(f32, @floatFromInt(pixel[0]));
            const g = @as(f32, @floatFromInt(pixel[1]));
            const b = @as(f32, @floatFromInt(pixel[2]));
            return switch (component) {
                .gray, .y => 0.299 * r + 0.587 * g + 0.114 * b - 128.0,
                .cb => -0.168736 * r - 0.331264 * g + 0.5 * b,
                .cr => 0.5 * r - 0.418688 * g - 0.081312 * b,
            };
        },
    };
}
