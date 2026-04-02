const std = @import("std");
const view_mod = @import("../../view.zig");

pub const ImageConstViewU8 = view_mod.ImageConstViewU8;

pub fn filteredScanlineLen(view: ImageConstViewU8) usize {
    return 1 + view.layout.width * view.layout.descriptor.bytesPerPixel();
}

pub fn writeFilteredNone(writer: *std.Io.Writer, view: ImageConstViewU8) !void {
    for (0..view.layout.height) |y| {
        try writer.writeByte(0);
        try writer.writeAll(view.row(y));
    }
}
