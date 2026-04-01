const std = @import("std");
const bitreader = @import("bitreader.zig");
const huffman = @import("huffman.zig");
const idct = @import("idct.zig");
const jpeg_types = @import("types.zig");

pub const ImageU8 = jpeg_types.ImageU8;
const BitReader = bitreader.BitReader;
const ComponentPlane = jpeg_types.ComponentPlane;
const Frame = jpeg_types.Frame;
const FrameComponent = jpeg_types.FrameComponent;
const HuffmanTable = jpeg_types.HuffmanTable;
const QuantTable = jpeg_types.QuantTable;
const ScanComponent = jpeg_types.ScanComponent;
const zigzag = jpeg_types.zigzag;

const ProgressiveComponent = struct {
    coeffs: []i32,
    blocks_x: usize,
    blocks_y: usize,
    scan_blocks_x: usize,
    scan_blocks_y: usize,
    actual_width: usize,
    actual_height: usize,
    h: u8,
    v: u8,
    dc_pred: i32 = 0,
};

const ScanTarget = struct {
    scan: ScanComponent,
    component_index: usize,
};

const Decoder = struct {
    allocator: std.mem.Allocator,
    bytes: []const u8,
    pos: usize = 0,
    frame: Frame = .{},
    quant_tables: [4]QuantTable = [_]QuantTable{.{}} ** 4,
    dc_tables: [4]HuffmanTable = [_]HuffmanTable{.{}} ** 4,
    ac_tables: [4]HuffmanTable = [_]HuffmanTable{.{}} ** 4,
    restart_interval: usize = 0,
    seen_scan: bool = false,
    progressive_components: [3]ProgressiveComponent = undefined,
    progressive_initialized: bool = false,

    fn decode(self: *Decoder) !ImageU8 {
        try self.expectMarker(0xD8);
        errdefer self.deinitProgressiveComponents();

        while (self.pos < self.bytes.len) {
            const marker = try self.nextMarker();
            switch (marker) {
                0xD9 => break,
                0xC0 => try self.parseSof(false),
                0xC2 => try self.parseSof(true),
                0xC4 => try self.parseDht(),
                0xDB => try self.parseDqt(),
                0xDD => try self.parseDri(),
                0xDA => {
                    self.seen_scan = true;
                    if (self.frame.progressive) {
                        try self.ensureProgressiveState();
                        try self.parseProgressiveScan();
                    } else {
                        return self.parseBaselineScan();
                    }
                },
                0xE0...0xEF, 0xFE => try self.skipSegment(),
                else => {
                    if (marker >= 0xD0 and marker <= 0xD7) return error.InvalidJpegMarker;
                    try self.skipSegment();
                },
            }
        }

        if (!self.seen_scan) return error.MissingJpegScan;
        if (!self.frame.progressive) return error.MissingJpegScan;

        const image = try self.finishProgressive();
        self.deinitProgressiveComponents();
        return image;
    }

    fn deinitProgressiveComponents(self: *Decoder) void {
        if (!self.progressive_initialized) return;
        for (0..self.frame.component_count) |i| {
            self.allocator.free(self.progressive_components[i].coeffs);
        }
        self.progressive_initialized = false;
    }

    fn expectMarker(self: *Decoder, marker: u8) !void {
        const found = try self.nextMarker();
        if (found != marker) return error.InvalidJpegHeader;
    }

    fn nextMarker(self: *Decoder) !u8 {
        while (self.pos < self.bytes.len and self.bytes[self.pos] != 0xFF) : (self.pos += 1) {}
        if (self.pos >= self.bytes.len) return error.InvalidJpegMarker;
        while (self.pos < self.bytes.len and self.bytes[self.pos] == 0xFF) : (self.pos += 1) {}
        if (self.pos >= self.bytes.len) return error.InvalidJpegMarker;
        const marker = self.bytes[self.pos];
        self.pos += 1;
        return marker;
    }

    fn skipSegment(self: *Decoder) !void {
        const len = try self.readSegmentLength();
        if (self.pos + len > self.bytes.len) return error.InvalidJpegSegment;
        self.pos += len;
    }

    fn parseDqt(self: *Decoder) !void {
        var remaining = try self.readSegmentLength();
        while (remaining > 0) {
            if (remaining < 65) return error.InvalidJpegSegment;
            const info = try self.readByte();
            remaining -= 1;
            const precision = info >> 4;
            const table_id = info & 0x0f;
            if (precision != 0 or table_id >= self.quant_tables.len) return error.UnsupportedJpegQuantization;
            if (remaining < 64) return error.InvalidJpegSegment;
            var table = &self.quant_tables[table_id];
            for (0..64) |i| {
                table.values[jpeg_types.zigzag[i]] = try self.readByte();
            }
            table.defined = true;
            remaining -= 64;
        }
    }

    fn parseDht(self: *Decoder) !void {
        var remaining = try self.readSegmentLength();
        while (remaining > 0) {
            if (remaining < 17) return error.InvalidJpegSegment;
            const info = try self.readByte();
            remaining -= 1;
            const class = info >> 4;
            const table_id = info & 0x0f;
            if (class > 1 or table_id >= 4) return error.UnsupportedJpegHuffmanTable;

            var counts = [_]u8{0} ** 16;
            var total: usize = 0;
            for (0..16) |i| {
                counts[i] = try self.readByte();
                total += counts[i];
            }
            remaining -= 16;
            if (remaining < total) return error.InvalidJpegSegment;

            var table = if (class == 0) &self.dc_tables[table_id] else &self.ac_tables[table_id];
            table.* = .{};
            table.counts = counts;
            table.symbol_count = total;
            for (0..total) |i| {
                table.symbols[i] = try self.readByte();
            }
            table.build();
            table.defined = true;
            remaining -= total;
        }
    }

    fn parseDri(self: *Decoder) !void {
        const len = try self.readSegmentLength();
        if (len != 2) return error.InvalidJpegSegment;
        self.restart_interval = try self.readU16be();
    }

    fn parseSof(self: *Decoder, progressive: bool) !void {
        const len = try self.readSegmentLength();
        if (len < 6) return error.InvalidJpegSegment;
        const precision = try self.readByte();
        if (precision != 8) return error.UnsupportedJpegPrecision;
        const height = try self.readU16be();
        const width = try self.readU16be();
        const component_count = try self.readByte();
        if (width == 0 or height == 0) return error.InvalidJpegDimensions;
        if (component_count != 1 and component_count != 3) return error.UnsupportedJpegComponents;
        if (len != 6 + component_count * 3) return error.InvalidJpegSegment;

        var frame = Frame{
            .width = width,
            .height = height,
            .component_count = component_count,
            .progressive = progressive,
        };
        for (0..component_count) |i| {
            const id = try self.readByte();
            const hv = try self.readByte();
            const quant_table = try self.readByte();
            const h = hv >> 4;
            const v = hv & 0x0f;
            if (h == 0 or v == 0 or quant_table >= 4) return error.UnsupportedJpegSampling;
            frame.components[i] = .{
                .id = id,
                .h = h,
                .v = v,
                .quant_table = quant_table,
            };
            frame.max_h = @max(frame.max_h, h);
            frame.max_v = @max(frame.max_v, v);
        }
        self.frame = frame;
    }

    fn parseBaselineScan(self: *Decoder) !ImageU8 {
        if (self.frame.width == 0 or self.frame.height == 0) return error.MissingJpegFrame;

        const len = try self.readSegmentLength();
        if (len < 6) return error.InvalidJpegSegment;
        const scan_component_count = try self.readByte();
        if (scan_component_count != self.frame.component_count) return error.UnsupportedJpegScan;
        if (len != 4 + scan_component_count * 2) return error.InvalidJpegSegment;

        var scan_components: [3]ScanComponent = undefined;
        for (0..scan_component_count) |i| {
            const id = try self.readByte();
            const selectors = try self.readByte();
            scan_components[i] = .{
                .id = id,
                .dc_table = selectors >> 4,
                .ac_table = selectors & 0x0f,
            };
        }
        const spectral_start = try self.readByte();
        const spectral_end = try self.readByte();
        const successive = try self.readByte();
        if (spectral_start != 0 or spectral_end != 63 or successive != 0) return error.UnsupportedJpegScan;

        for (scan_components[0..scan_component_count]) |scan_component| {
            const frame_component = self.findFrameComponent(scan_component.id) orelse return error.UnsupportedJpegScan;
            frame_component.dc_table = scan_component.dc_table;
            frame_component.ac_table = scan_component.ac_table;
            if (frame_component.dc_table >= 4 or frame_component.ac_table >= 4) return error.UnsupportedJpegHuffmanTable;
        }

        return self.decodeEntropy();
    }

    fn parseProgressiveScan(self: *Decoder) !void {
        if (self.frame.width == 0 or self.frame.height == 0) return error.MissingJpegFrame;

        const len = try self.readSegmentLength();
        if (len < 6) return error.InvalidJpegSegment;
        const scan_component_count = try self.readByte();
        if (scan_component_count == 0 or scan_component_count > self.frame.component_count) return error.UnsupportedJpegScan;
        if (len != 4 + scan_component_count * 2) return error.InvalidJpegSegment;

        var scan_components: [3]ScanTarget = undefined;
        for (0..scan_component_count) |i| {
            const id = try self.readByte();
            const selectors = try self.readByte();
            const component_index = self.findFrameComponentIndex(id) orelse return error.UnsupportedJpegScan;
            scan_components[i] = .{
                .scan = .{
                    .id = id,
                    .dc_table = selectors >> 4,
                    .ac_table = selectors & 0x0f,
                },
                .component_index = component_index,
            };
            const frame_component = &self.frame.components[component_index];
            frame_component.dc_table = scan_components[i].scan.dc_table;
            frame_component.ac_table = scan_components[i].scan.ac_table;
            if (frame_component.dc_table >= 4 or frame_component.ac_table >= 4) return error.UnsupportedJpegHuffmanTable;
        }

        const spectral_start = try self.readByte();
        const spectral_end = try self.readByte();
        const successive = try self.readByte();
        const approx_high = successive >> 4;
        const approx_low = successive & 0x0f;

        if (spectral_start > spectral_end or spectral_end > 63) return error.UnsupportedJpegScan;
        if ((spectral_start == 0 and spectral_end != 0) or (spectral_start != 0 and scan_component_count != 1)) {
            return error.UnsupportedJpegScan;
        }
        if (approx_high != 0 and approx_high - 1 != approx_low) return error.UnsupportedJpegScan;

        try self.decodeProgressiveEntropy(scan_components[0..scan_component_count], spectral_start, spectral_end, approx_high, approx_low);
    }

    fn ensureProgressiveState(self: *Decoder) !void {
        if (self.progressive_initialized) return;

        const mcu_width = @as(usize, self.frame.max_h) * 8;
        const mcu_height = @as(usize, self.frame.max_v) * 8;
        const mcus_x = idct.divCeil(self.frame.width, mcu_width);
        const mcus_y = idct.divCeil(self.frame.height, mcu_height);

        for (0..self.frame.component_count) |i| {
            const component = self.frame.components[i];
            const actual_width = idct.divCeil(self.frame.width * @as(usize, component.h), @as(usize, self.frame.max_h));
            const actual_height = idct.divCeil(self.frame.height * @as(usize, component.v), @as(usize, self.frame.max_v));
            const blocks_x = mcus_x * @as(usize, component.h);
            const blocks_y = mcus_y * @as(usize, component.v);
            const coeffs = try self.allocator.alloc(i32, blocks_x * blocks_y * 64);
            @memset(coeffs, 0);
            self.progressive_components[i] = .{
                .coeffs = coeffs,
                .blocks_x = blocks_x,
                .blocks_y = blocks_y,
                .scan_blocks_x = idct.divCeil(actual_width, 8),
                .scan_blocks_y = idct.divCeil(actual_height, 8),
                .actual_width = actual_width,
                .actual_height = actual_height,
                .h = component.h,
                .v = component.v,
            };
        }

        self.progressive_initialized = true;
    }

    fn decodeProgressiveEntropy(
        self: *Decoder,
        scan_components: []const ScanTarget,
        spectral_start: u8,
        spectral_end: u8,
        approx_high: u8,
        approx_low: u8,
    ) !void {
        var reader = BitReader{
            .bytes = self.bytes,
            .pos = self.pos,
        };
        var restart_countdown = self.restart_interval;
        var eob_run: usize = 0;

        if (scan_components.len == 1) {
            const scan_target = scan_components[0];
            const prog = &self.progressive_components[scan_target.component_index];

            for (0..prog.scan_blocks_y) |block_y| {
                for (0..prog.scan_blocks_x) |block_x| {
                    const coeffs = self.progressiveBlockSlice(prog, block_x, block_y);
                    if (spectral_start == 0) {
                        if (approx_high == 0) {
                            try self.decodeProgressiveDcFirst(&reader, scan_target.scan.dc_table, prog, coeffs, approx_low);
                        } else {
                            try refineCoefficientBit(&reader, &coeffs[0], approx_low);
                        }
                    } else if (approx_high == 0) {
                        try self.decodeProgressiveAcFirst(&reader, scan_target.scan.ac_table, coeffs, spectral_start, spectral_end, approx_low, &eob_run);
                    } else {
                        try self.decodeProgressiveAcRefine(&reader, scan_target.scan.ac_table, coeffs, spectral_start, spectral_end, approx_low, &eob_run);
                    }

                    try self.maybeConsumeRestart(&reader, &restart_countdown, &eob_run);
                }
            }
        } else {
            const mcu_width = @as(usize, self.frame.max_h) * 8;
            const mcu_height = @as(usize, self.frame.max_v) * 8;
            const mcus_x = idct.divCeil(self.frame.width, mcu_width);
            const mcus_y = idct.divCeil(self.frame.height, mcu_height);

            for (0..mcus_y) |mcu_y| {
                for (0..mcus_x) |mcu_x| {
                    for (scan_components) |scan_target| {
                        const component = self.frame.components[scan_target.component_index];
                        const prog = &self.progressive_components[scan_target.component_index];
                        for (0..component.v) |block_y| {
                            for (0..component.h) |block_x| {
                                const prog_block_x = mcu_x * @as(usize, component.h) + block_x;
                                const prog_block_y = mcu_y * @as(usize, component.v) + block_y;
                                if (prog_block_x >= prog.blocks_x or prog_block_y >= prog.blocks_y) continue;
                                const coeffs = self.progressiveBlockSlice(
                                    prog,
                                    prog_block_x,
                                    prog_block_y,
                                );
                                if (approx_high == 0) {
                                    try self.decodeProgressiveDcFirst(&reader, scan_target.scan.dc_table, prog, coeffs, approx_low);
                                } else {
                                    try refineCoefficientBit(&reader, &coeffs[0], approx_low);
                                }
                            }
                        }
                    }

                    try self.maybeConsumeRestart(&reader, &restart_countdown, &eob_run);
                }
            }
        }

        self.pos = reader.pos;
    }

    fn maybeConsumeRestart(
        self: *Decoder,
        reader: *BitReader,
        restart_countdown: *usize,
        eob_run: *usize,
    ) !void {
        if (self.restart_interval == 0) return;

        restart_countdown.* -= 1;
        if (restart_countdown.* != 0) return;

        reader.alignToByte();
        try reader.consumeRestart();
        for (0..self.frame.component_count) |i| {
            self.progressive_components[i].dc_pred = 0;
        }
        eob_run.* = 0;
        restart_countdown.* = self.restart_interval;
    }

    fn decodeProgressiveDcFirst(
        self: *Decoder,
        reader: *BitReader,
        table_id: u8,
        prog: *ProgressiveComponent,
        coeffs: *[64]i32,
        approx_low: u8,
    ) !void {
        if (table_id >= self.dc_tables.len or !self.dc_tables[table_id].defined) return error.InvalidJpegData;
        const dc_len = try huffman.decodeSymbol(reader, &self.dc_tables[table_id]);
        const dc_diff = try huffman.receiveAndExtendBits(reader, dc_len);
        prog.dc_pred += dc_diff << @intCast(approx_low);
        coeffs[0] = prog.dc_pred;
    }

    fn decodeProgressiveAcFirst(
        self: *Decoder,
        reader: *BitReader,
        table_id: u8,
        coeffs: *[64]i32,
        spectral_start: u8,
        spectral_end: u8,
        approx_low: u8,
        eob_run: *usize,
    ) !void {
        if (table_id >= self.ac_tables.len or !self.ac_tables[table_id].defined) return error.InvalidJpegData;
        if (eob_run.* > 0) {
            eob_run.* -= 1;
            return;
        }

        var k: usize = spectral_start;
        while (k <= spectral_end) {
            const symbol = try huffman.decodeSymbol(reader, &self.ac_tables[table_id]);
            const run = symbol >> 4;
            const size = symbol & 0x0f;
            if (size == 0) {
                if (run == 15) {
                    k += 16;
                    continue;
                }
                var new_eob_run: usize = @as(usize, 1) << @intCast(run);
                if (run > 0) new_eob_run += @as(usize, @intCast(try reader.readBits(@intCast(run))));
                eob_run.* = new_eob_run - 1;
                return;
            }

            k += run;
            if (k > spectral_end) return error.InvalidJpegData;
            coeffs[zigzag[k]] = (try huffman.receiveAndExtendBits(reader, size)) << @intCast(approx_low);
            k += 1;
        }
    }

    fn decodeProgressiveAcRefine(
        self: *Decoder,
        reader: *BitReader,
        table_id: u8,
        coeffs: *[64]i32,
        spectral_start: u8,
        spectral_end: u8,
        approx_low: u8,
        eob_run: *usize,
    ) !void {
        if (table_id >= self.ac_tables.len or !self.ac_tables[table_id].defined) return error.InvalidJpegData;

        const refine_value: i32 = @as(i32, 1) << @intCast(approx_low);
        if (eob_run.* > 0) {
            try refineExistingCoefficients(reader, coeffs, spectral_start, spectral_end, approx_low);
            eob_run.* -= 1;
            return;
        }

        var k: usize = spectral_start;
        while (k <= spectral_end) {
            const zz = zigzag[k];
            if (coeffs[zz] != 0) {
                try refineCoefficientBit(reader, &coeffs[zz], approx_low);
                k += 1;
                continue;
            }

            const symbol = try huffman.decodeSymbol(reader, &self.ac_tables[table_id]);
            var run: usize = symbol >> 4;
            const size = symbol & 0x0f;

            if (size == 0) {
                if (run < 15) {
                    var new_eob_run: usize = @as(usize, 1) << @intCast(run);
                    if (run > 0) new_eob_run += @as(usize, @intCast(try reader.readBits(@intCast(run))));
                    try refineExistingCoefficients(reader, coeffs, @intCast(k), spectral_end, approx_low);
                    eob_run.* = new_eob_run - 1;
                    return;
                }
                run = 16;
            } else if (size != 1) {
                return error.InvalidJpegData;
            }

            const new_coeff: i32 = if (try reader.readBit() == 1) refine_value else -refine_value;
            while (true) {
                const idx = zigzag[k];
                if (coeffs[idx] != 0) {
                    try refineCoefficientBit(reader, &coeffs[idx], approx_low);
                } else {
                    if (run == 0) break;
                    run -= 1;
                }
                k += 1;
                if (k > spectral_end) return error.InvalidJpegData;
            }

            coeffs[zigzag[k]] = new_coeff;
            k += 1;
        }
    }

    fn progressiveBlockSlice(self: *Decoder, prog: *ProgressiveComponent, block_x: usize, block_y: usize) *[64]i32 {
        _ = self;
        const index = (block_y * prog.blocks_x + block_x) * 64;
        return @ptrCast(prog.coeffs[index .. index + 64].ptr);
    }

    fn finishProgressive(self: *Decoder) !ImageU8 {
        if (!self.progressive_initialized) return error.MissingJpegScan;

        var planes: [3]ComponentPlane = undefined;
        for (0..self.frame.component_count) |i| {
            const component = self.frame.components[i];
            const prog = self.progressive_components[i];
            if (!self.quant_tables[component.quant_table].defined) return error.InvalidJpegData;

            planes[i] = .{
                .samples = try self.allocator.alloc(u8, prog.blocks_x * 8 * prog.blocks_y * 8),
                .plane_width = prog.blocks_x * 8,
                .plane_height = prog.blocks_y * 8,
                .actual_width = prog.actual_width,
                .actual_height = prog.actual_height,
                .h = prog.h,
                .v = prog.v,
            };
            @memset(planes[i].samples, 0);

            for (0..prog.blocks_y) |block_y| {
                for (0..prog.blocks_x) |block_x| {
                    const coeffs = self.progressiveBlockSlice(&self.progressive_components[i], block_x, block_y);
                    const samples = idct.idctBlock(coeffs, &self.quant_tables[component.quant_table].values);
                    try idct.writeBlock(&planes[i], block_x, block_y, &samples);
                }
            }
        }
        defer for (planes[0..self.frame.component_count]) |plane| self.allocator.free(plane.samples);

        return self.renderImageFromPlanes(planes);
    }

    fn decodeEntropy(self: *Decoder) !ImageU8 {
        if (self.frame.max_h == 0 or self.frame.max_v == 0) return error.MissingJpegFrame;

        var planes: [3]ComponentPlane = undefined;
        const mcu_width = @as(usize, self.frame.max_h) * 8;
        const mcu_height = @as(usize, self.frame.max_v) * 8;
        const mcus_x = idct.divCeil(self.frame.width, mcu_width);
        const mcus_y = idct.divCeil(self.frame.height, mcu_height);

        for (0..self.frame.component_count) |i| {
            const component = self.frame.components[i];
            if (!self.quant_tables[component.quant_table].defined) return error.InvalidJpegData;
            if (!self.dc_tables[component.dc_table].defined or !self.ac_tables[component.ac_table].defined) {
                return error.InvalidJpegData;
            }
            const plane_width = mcus_x * @as(usize, component.h) * 8;
            const plane_height = mcus_y * @as(usize, component.v) * 8;
            const actual_width = idct.divCeil(self.frame.width * @as(usize, component.h), @as(usize, self.frame.max_h));
            const actual_height = idct.divCeil(self.frame.height * @as(usize, component.v), @as(usize, self.frame.max_v));
            planes[i] = .{
                .samples = try self.allocator.alloc(u8, plane_width * plane_height),
                .plane_width = plane_width,
                .plane_height = plane_height,
                .actual_width = actual_width,
                .actual_height = actual_height,
                .h = component.h,
                .v = component.v,
            };
            @memset(planes[i].samples, 0);
        }
        defer for (planes[0..self.frame.component_count]) |plane| self.allocator.free(plane.samples);

        var reader = BitReader{
            .bytes = self.bytes,
            .pos = self.pos,
        };
        var restart_countdown = self.restart_interval;

        for (0..mcus_y) |mcu_y| {
            for (0..mcus_x) |mcu_x| {
                for (0..self.frame.component_count) |i| {
                    const component = self.frame.components[i];
                    for (0..component.v) |block_y| {
                        for (0..component.h) |block_x| {
                            var coeffs = [_]i32{0} ** 64;
                            try huffman.decodeBlock(
                                &reader,
                                &self.dc_tables[component.dc_table],
                                &self.ac_tables[component.ac_table],
                                &planes[i].dc_pred,
                                &coeffs,
                            );
                            const samples = idct.idctBlock(&coeffs, &self.quant_tables[component.quant_table].values);
                            try idct.writeBlock(
                                &planes[i],
                                mcu_x * @as(usize, component.h) + block_x,
                                mcu_y * @as(usize, component.v) + block_y,
                                &samples,
                            );
                        }
                    }
                }

                if (self.restart_interval > 0) {
                    restart_countdown -= 1;
                    if (restart_countdown == 0) {
                        reader.alignToByte();
                        try reader.consumeRestart();
                        for (0..self.frame.component_count) |i| {
                            planes[i].dc_pred = 0;
                        }
                        restart_countdown = self.restart_interval;
                    }
                }
            }
        }

        self.pos = reader.pos;
        return self.renderImageFromPlanes(planes);
    }

    fn renderImageFromPlanes(self: *Decoder, planes: [3]ComponentPlane) !ImageU8 {
        var image = try ImageU8.init(self.allocator, self.frame.width, self.frame.height, 3);
        errdefer image.deinit();

        if (self.frame.component_count == 1) {
            const plane = planes[0];
            for (0..self.frame.height) |y| {
                for (0..self.frame.width) |x| {
                    const sample = plane.samples[y * plane.plane_width + x];
                    const dst = image.pixelIndex(x, y, 0);
                    image.data[dst] = sample;
                    image.data[dst + 1] = sample;
                    image.data[dst + 2] = sample;
                }
            }
            return image;
        }

        const y_plane = planes[0];
        const cb_plane = planes[1];
        const cr_plane = planes[2];
        for (0..self.frame.height) |y| {
            for (0..self.frame.width) |x| {
                const yv = idct.samplePlane(&y_plane, x, y, self.frame.max_h, self.frame.max_v);
                const cbv = idct.samplePlane(&cb_plane, x, y, self.frame.max_h, self.frame.max_v);
                const crv = idct.samplePlane(&cr_plane, x, y, self.frame.max_h, self.frame.max_v);

                const yf = @as(f32, @floatFromInt(yv));
                const cbf = @as(f32, @floatFromInt(cbv)) - 128.0;
                const crf = @as(f32, @floatFromInt(crv)) - 128.0;

                const r = clampToU8(yf + 1.402 * crf);
                const g = clampToU8(yf - 0.344136 * cbf - 0.714136 * crf);
                const b = clampToU8(yf + 1.772 * cbf);

                const dst = image.pixelIndex(x, y, 0);
                image.data[dst] = r;
                image.data[dst + 1] = g;
                image.data[dst + 2] = b;
            }
        }
        return image;
    }

    fn findFrameComponent(self: *Decoder, id: u8) ?*FrameComponent {
        for (self.frame.components[0..self.frame.component_count]) |*component| {
            if (component.id == id) return component;
        }
        return null;
    }

    fn findFrameComponentIndex(self: *Decoder, id: u8) ?usize {
        for (self.frame.components[0..self.frame.component_count], 0..) |component, index| {
            if (component.id == id) return index;
        }
        return null;
    }

    fn readSegmentLength(self: *Decoder) !usize {
        const len = try self.readU16be();
        if (len < 2) return error.InvalidJpegSegment;
        return len - 2;
    }

    fn readByte(self: *Decoder) !u8 {
        if (self.pos >= self.bytes.len) return error.InvalidJpegData;
        const value = self.bytes[self.pos];
        self.pos += 1;
        return value;
    }

    fn readU16be(self: *Decoder) !usize {
        if (self.pos + 2 > self.bytes.len) return error.InvalidJpegData;
        const value = (@as(u16, self.bytes[self.pos]) << 8) | @as(u16, self.bytes[self.pos + 1]);
        self.pos += 2;
        return value;
    }
};

fn refineExistingCoefficients(
    reader: *BitReader,
    coeffs: *[64]i32,
    spectral_start: u8,
    spectral_end: u8,
    approx_low: u8,
) !void {
    var k: usize = spectral_start;
    while (k <= spectral_end) : (k += 1) {
        const idx = zigzag[k];
        if (coeffs[idx] != 0) try refineCoefficientBit(reader, &coeffs[idx], approx_low);
    }
}

fn refineCoefficientBit(reader: *BitReader, coeff: *i32, approx_low: u8) !void {
    if (try reader.readBit() == 0) return;
    if (coeff.* == 0) return;

    const refine_value: i32 = @as(i32, 1) << @intCast(approx_low);
    if (coeff.* > 0) {
        coeff.* += refine_value;
    } else {
        coeff.* -= refine_value;
    }
}

fn clampToU8(value: f32) u8 {
    if (value <= 0) return 0;
    if (value >= 255) return 255;
    return @intFromFloat(@round(value));
}

pub fn decodeRgb8(allocator: std.mem.Allocator, bytes: []const u8) !ImageU8 {
    var decoder = Decoder{
        .allocator = allocator,
        .bytes = bytes,
    };
    return decoder.decode();
}
