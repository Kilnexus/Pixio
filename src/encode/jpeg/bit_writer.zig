const std = @import("std");

pub const BitWriter = struct {
    allocator: std.mem.Allocator,
    bytes: std.ArrayListUnmanaged(u8) = .empty,
    current: u8 = 0,
    bits_used: u8 = 0,

    pub fn deinit(self: *BitWriter) void {
        self.bytes.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn writeBits(self: *BitWriter, bits: u16, len: u8) !void {
        var remaining = len;
        while (remaining > 0) {
            remaining -= 1;
            const bit = @as(u8, @intCast((bits >> @intCast(remaining)) & 1));
            self.current = (self.current << 1) | bit;
            self.bits_used += 1;
            if (self.bits_used == 8) try self.flushCurrentByte();
        }
    }

    pub fn flush(self: *BitWriter) !void {
        if (self.bits_used == 0) return;

        const remaining = 8 - self.bits_used;
        const pad_mask = @as(u8, @intCast((@as(u16, 1) << @intCast(remaining)) - 1));
        self.current = (self.current << @intCast(remaining)) | pad_mask;
        try self.flushCurrentByte();
    }

    pub fn toOwnedSlice(self: *BitWriter) ![]u8 {
        return self.bytes.toOwnedSlice(self.allocator);
    }

    fn flushCurrentByte(self: *BitWriter) !void {
        const byte = self.current;
        self.current = 0;
        self.bits_used = 0;

        try self.bytes.append(self.allocator, byte);
        if (byte == 0xFF) try self.bytes.append(self.allocator, 0x00);
    }
};
