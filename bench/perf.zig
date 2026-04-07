const std = @import("std");
const pixio = @import("Pixio");

const BenchCase = struct {
    name: []const u8,
    iterations: usize,
    run: *const fn (std.mem.Allocator, *const pixio.ImageU8) anyerror!void,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var image = try buildGradientImage(allocator, 1920, 1080, 3);
    defer image.deinit();

    const cases = [_]BenchCase{
        .{ .name = "resize-bilinear-640x640", .iterations = 8, .run = benchResizeBilinear },
        .{ .name = "resize-lanczos3-640x640", .iterations = 4, .run = benchResizeLanczos3 },
        .{ .name = "gaussian-blur-s1.4", .iterations = 4, .run = benchGaussianBlur },
        .{ .name = "prepare-tensor-nchw-batch4", .iterations = 8, .run = benchPrepareTensorBatch },
    };

    std.debug.print("Pixio benchmark on {d}x{d}x{d}\n", .{ image.width, image.height, image.channels });

    for (cases) |bench| {
        const elapsed_ns = try runCase(allocator, &image, bench);
        const elapsed_ms = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, std.time.ns_per_ms);
        const per_iter_ms = elapsed_ms / @as(f64, @floatFromInt(bench.iterations));
        std.debug.print("{s}: total {d:.3} ms, iter {d:.3} ms\n", .{ bench.name, elapsed_ms, per_iter_ms });
    }
}

fn runCase(
    allocator: std.mem.Allocator,
    image: *const pixio.ImageU8,
    bench: BenchCase,
) !u64 {
    var timer = try std.time.Timer.start();
    for (0..bench.iterations) |_| {
        try bench.run(allocator, image);
    }
    return timer.read();
}

fn benchResizeBilinear(allocator: std.mem.Allocator, image: *const pixio.ImageU8) !void {
    var dst = try pixio.resizeBilinear(allocator, image, 640, 640);
    defer dst.deinit();
    std.mem.doNotOptimizeAway(dst.data[0]);
}

fn benchResizeLanczos3(allocator: std.mem.Allocator, image: *const pixio.ImageU8) !void {
    var dst = try pixio.resizeLanczos3(allocator, image, 640, 640);
    defer dst.deinit();
    std.mem.doNotOptimizeAway(dst.data[0]);
}

fn benchGaussianBlur(allocator: std.mem.Allocator, image: *const pixio.ImageU8) !void {
    var dst = try pixio.gaussianBlur(allocator, image, 1.4);
    defer dst.deinit();
    std.mem.doNotOptimizeAway(dst.data[0]);
}

fn benchPrepareTensorBatch(allocator: std.mem.Allocator, image: *const pixio.ImageU8) !void {
    const sources = [_]*const pixio.ImageU8{ image, image, image, image };
    var batch = try pixio.prepareTensorNchwBatch(allocator, &sources, .{
        .target_width = 640,
        .target_height = 640,
        .mode = .letterbox,
        .kernel = .bilinear,
        .output_pixel_format = .rgb8,
    });
    defer batch.deinit();
    std.mem.doNotOptimizeAway(batch.tensor.data[0]);
}

fn buildGradientImage(
    allocator: std.mem.Allocator,
    width: usize,
    height: usize,
    channels: usize,
) !pixio.ImageU8 {
    var image = try pixio.ImageU8.init(allocator, width, height, channels);
    errdefer image.deinit();

    for (0..height) |y| {
        for (0..width) |x| {
            const base = (y * width + x) * channels;
            image.data[base] = @intCast((x * 255) / @max(width - 1, 1));
            if (channels > 1) image.data[base + 1] = @intCast((y * 255) / @max(height - 1, 1));
            if (channels > 2) image.data[base + 2] = @intCast(((x + y) * 255) / @max(width + height - 2, 1));
            if (channels > 3) image.data[base + 3] = 0xff;
        }
    }

    return image;
}
