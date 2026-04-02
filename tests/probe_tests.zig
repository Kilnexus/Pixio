const std = @import("std");
const imaging = @import("Pixio");
const helpers = @import("helpers.zig");

test "probeInfo reads repository sample png metadata" {
    const testing = std.testing;

    const info = try imaging.probeFileInfo(testing.allocator, "testdata/000_0001.png");
    try testing.expectEqual(imaging.ImageFormat.png, info.format);
    try testing.expectEqual(@as(usize, 134), info.width);
    try testing.expectEqual(@as(usize, 128), info.height);
    try testing.expectEqual(@as(usize, 3), info.channels);
    try testing.expectEqual(@as(usize, 3), info.native_channels);
    try testing.expect(!info.has_alpha);
}

test "probeInfo reports alpha for png tRNS" {
    const testing = std.testing;

    const png = try helpers.decodeBase64Alloc(testing.allocator, "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQAAAAA3bvkkAAAAAnRSTlMAAQGU/a4AAAAKSURBVHicY2gAAACCAIF3zXK2AAAAAElFTkSuQmCC");
    defer testing.allocator.free(png);

    const info = try imaging.probeInfo(png);
    try testing.expectEqual(imaging.ImageFormat.png, info.format);
    try testing.expectEqual(@as(usize, 1), info.width);
    try testing.expectEqual(@as(usize, 1), info.height);
    try testing.expectEqual(@as(usize, 3), info.channels);
    try testing.expectEqual(@as(usize, 4), info.native_channels);
    try testing.expect(info.has_alpha);
}

test "probeFileInfo reports alpha for png tRNS" {
    const testing = std.testing;

    const png = try helpers.decodeBase64Alloc(testing.allocator, "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQAAAAA3bvkkAAAAAnRSTlMAAQGU/a4AAAAKSURBVHicY2gAAACCAIF3zXK2AAAAAElFTkSuQmCC");
    defer testing.allocator.free(png);

    const path = "._pixio_probe_trns.png";
    defer std.fs.cwd().deleteFile(path) catch {};
    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = png });

    const info = try imaging.probeFileInfo(testing.allocator, path);
    try testing.expectEqual(imaging.ImageFormat.png, info.format);
    try testing.expectEqual(@as(usize, 4), info.native_channels);
    try testing.expect(info.has_alpha);
}

test "probeInfo reads lossless webp metadata" {
    const testing = std.testing;

    const webp = try helpers.decodeBase64Alloc(testing.allocator, "UklGRh4AAABXRUJQVlA4TBEAAAAvAQAAAA+w//Mf8x8VMqL/AQA=");
    defer testing.allocator.free(webp);

    const info = try imaging.probeInfo(webp);
    try testing.expectEqual(imaging.ImageFormat.webp, info.format);
    try testing.expectEqual(@as(usize, 2), info.width);
    try testing.expectEqual(@as(usize, 1), info.height);
    try testing.expectEqual(@as(usize, 3), info.channels);
    try testing.expectEqual(@as(usize, 3), info.native_channels);
    try testing.expect(!info.has_alpha);
}

test "probeInfo separates default output channels from native alpha channels" {
    const testing = std.testing;

    const webp = try helpers.decodeBase64Alloc(testing.allocator, "UklGRhwAAABXRUJQVlA4TA8AAAAvAAAAEAcQ/Y8CBiKi/wEA");
    defer testing.allocator.free(webp);

    const info = try imaging.probeInfo(webp);
    try testing.expectEqual(@as(usize, 3), info.channels);
    try testing.expectEqual(@as(usize, 4), info.native_channels);
    try testing.expect(info.has_alpha);
}

test "probeWebpInfo distinguishes lossless and lossy bitstreams" {
    const testing = std.testing;

    const lossless = try helpers.decodeBase64Alloc(testing.allocator, "UklGRh4AAABXRUJQVlA4TBEAAAAvAQAAAA+w//Mf8x8VMqL/AQA=");
    defer testing.allocator.free(lossless);

    const lossy = try helpers.decodeBase64Alloc(testing.allocator, "UklGRkgAAABXRUJQVlA4IDwAAAAwAgCdASoCAAEAAAAAJaACdLoB+AADIQb7gAD5f/8uv//vTP/5zIj//2Z7/Znv9me/+zPf/maJjmP16AA=");
    defer testing.allocator.free(lossy);

    const lossless_info = try imaging.probeWebpInfo(lossless);
    try testing.expectEqual(@as(usize, 2), lossless_info.width);
    try testing.expectEqual(@as(usize, 1), lossless_info.height);
    try testing.expectEqual(@as(imaging.WebpInfo, lossless_info).kind, .vp8l);
    try testing.expect(!lossless_info.has_alpha);
    try testing.expect(!lossless_info.is_animated);

    const lossy_info = try imaging.probeWebpInfo(lossy);
    try testing.expectEqual(@as(usize, 2), lossy_info.width);
    try testing.expectEqual(@as(usize, 1), lossy_info.height);
    try testing.expectEqual(@as(imaging.WebpInfo, lossy_info).kind, .vp8);
    try testing.expect(!lossy_info.has_alpha);
    try testing.expect(!lossy_info.is_animated);
}

test "probeInfo reports metadata for animated webp variant" {
    const testing = std.testing;

    const animated_webp = try helpers.decodeBase64Alloc(testing.allocator, "UklGRsoAAABXRUJQVlA4WAoAAAACAAAAAAAAAAAAQU5JTQYAAAAAAAAAAABBTk1GSgAAAAAAAAAAAAAAAAAAAGQAAAJWUDggMgAAADABAJ0BKgEAAQABQCYloAADcAD+8ut///mwP/bz/wR6Af//0uD//pcH//S4P/SkAAAAQU5NRkwAAAAAAAAAAAAAAAAAAABkAAAAVlA4IDQAAAA0AQCdASoBAAEAAAAmJaAAA3AA/ukiH//3nz//ufP/+58/6M///yn7//I4//8jj/5QIAAA");
    defer testing.allocator.free(animated_webp);

    const animated_info = try imaging.probeWebpInfo(animated_webp);
    try testing.expectEqual(@as(usize, 1), animated_info.width);
    try testing.expectEqual(@as(usize, 1), animated_info.height);
    try testing.expect(animated_info.is_animated);
}

test "probeWebpInfo reports alpha for lossless rgba sample" {
    const testing = std.testing;

    const webp = try helpers.decodeBase64Alloc(testing.allocator, "UklGRhwAAABXRUJQVlA4TA8AAAAvAAAAEAcQ/Y8CBiKi/wEA");
    defer testing.allocator.free(webp);

    const info = try imaging.probeWebpInfo(webp);
    try testing.expectEqual(@as(usize, 1), info.width);
    try testing.expectEqual(@as(usize, 1), info.height);
    try testing.expectEqual(@as(imaging.WebpInfo, info).kind, .vp8l);
    try testing.expect(info.has_alpha);
}

test "findPrimaryChunk identifies webp payload kind" {
    const testing = std.testing;

    const bytes = try helpers.decodeBase64Alloc(testing.allocator, "UklGRh4AAABXRUJQVlA4TBEAAAAvAQAAAA+w//Mf8x8VMqL/AQA=");
    defer testing.allocator.free(bytes);

    const tag = try imaging.probeWebpPrimaryChunkTag(bytes);
    try testing.expectEqual(imaging.WebpChunkTag.vp8l, tag);
}

test "probeInfo rejects truncated fixed-layout headers" {
    const testing = std.testing;

    try testing.expectError(error.InvalidPngChunk, imaging.probeInfo("\x89PNG\r\n\x1a\n"));
    try testing.expectError(error.InvalidBmpHeader, imaging.probeInfo("BM"));
    try testing.expectError(error.InvalidGifHeader, imaging.probeInfo("GIF89a"));
    try testing.expectError(error.InvalidIcoHeader, imaging.probeInfo("\x00\x00\x01\x00"));
}
