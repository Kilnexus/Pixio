const std = @import("std");
const builtin = @import("builtin");
const imaging = @import("Pixio");
const helpers = @import("helpers.zig");

test "decodeRgb8 decodes repository sample png natively" {
    const testing = std.testing;

    var image = try imaging.decodeFileRgb8(testing.allocator, "testdata/000_0001.png");
    defer image.deinit();

    try testing.expectEqual(@as(usize, 134), image.width);
    try testing.expectEqual(@as(usize, 128), image.height);
    try testing.expectEqual(@as(usize, 3), image.channels);
}

test "decodeRgb8 decodes 24-bit bmp" {
    const testing = std.testing;

    const bmp = [_]u8{
        0x42, 0x4d, 0x46, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x36, 0x00, 0x00, 0x00,
        0x28, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00,
        0x18, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x00, 0x00, 0x13, 0x0b, 0x00, 0x00,
        0x13, 0x0b, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0xff, 0x00, 0xff, 0x00, 0x00, 0x00,
    };

    var image = try imaging.decodeRgb8(testing.allocator, &bmp);
    defer image.deinit();

    try testing.expectEqual(@as(usize, 2), image.width);
    try testing.expectEqual(@as(usize, 1), image.height);
    try testing.expectEqualSlices(u8, &[_]u8{ 0xff, 0x00, 0x00 }, image.data[0..3]);
    try testing.expectEqualSlices(u8, &[_]u8{ 0x00, 0xff, 0x00 }, image.data[3..6]);
}

test "decodeRgb8 decodes 8-bit palette bmp" {
    const testing = std.testing;

    const bmp = try helpers.decodeBase64Alloc(testing.allocator, "Qk1CAAAAAAAAAD4AAAAoAAAAAgAAAAEAAAABAAgAAAAAAAQAAAATCwAAEwsAAAIAAAAAAAAAAAD/AAD/AAAAAQAA");
    defer testing.allocator.free(bmp);

    var image = try imaging.decodeRgb8(testing.allocator, bmp);
    defer image.deinit();

    try testing.expectEqual(@as(usize, 2), image.width);
    try testing.expectEqual(@as(usize, 1), image.height);
    try testing.expectEqualSlices(u8, &[_]u8{ 0xff, 0x00, 0x00 }, image.data[0..3]);
    try testing.expectEqualSlices(u8, &[_]u8{ 0x00, 0xff, 0x00 }, image.data[3..6]);
}

test "decodeRgb8 decodes baseline jpeg" {
    const testing = std.testing;

    const jpeg = try helpers.decodeBase64Alloc(testing.allocator, "/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAABAAIDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwC7p3/IMtP+uKf+giiiivzefxM/Lcy/32t/il+bP//Z");
    defer testing.allocator.free(jpeg);

    var image = try imaging.decodeRgb8(testing.allocator, jpeg);
    defer image.deinit();

    try testing.expectEqual(@as(usize, 2), image.width);
    try testing.expectEqual(@as(usize, 1), image.height);
    try testing.expectEqual(@as(usize, 3), image.channels);
    try testing.expect(image.data[2] < image.data[0]);
    try testing.expect(image.data[2] < image.data[1]);
    try testing.expect(image.data[4] > image.data[3]);
    try testing.expect(image.data[4] > image.data[5]);
    try testing.expect(!std.mem.eql(u8, image.data[0..3], image.data[3..6]));
}

test "decodeRgb8 decodes progressive jpeg" {
    const testing = std.testing;

    const jpeg = try helpers.decodeBase64Alloc(testing.allocator, "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wgARCAABAAIDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAX/xAAVAQEBAAAAAAAAAAAAAAAAAAAFBv/aAAwDAQACEAMQAAABigy4/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABAH/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPxB//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPxB//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxB//9k=");
    defer testing.allocator.free(jpeg);

    var image = try imaging.decodeRgb8(testing.allocator, jpeg);
    defer image.deinit();

    try testing.expectEqual(@as(usize, 2), image.width);
    try testing.expectEqual(@as(usize, 1), image.height);
    try testing.expectEqual(@as(usize, 3), image.channels);
    try testing.expectEqualSlices(u8, &[_]u8{
        254, 0, 0,
        254, 0, 0,
    }, image.data);
}

test "decodeRgb8 decodes palette gif" {
    const testing = std.testing;

    const gif = try helpers.decodeBase64Alloc(testing.allocator,
        "R0lGODlhAgABAPcAAAAAAAAAMwAAZgAAmQAAzAAA/wArAAArMwArZgArmQArzAAr/wBVAABVMwBVZgBVmQBVzABV"
        ++ "/wCAAACAMwCAZgCAmQCAzACA/wCqAACqMwCqZgCqmQCqzACq/wDVAADVMwDVZgDVmQDVzADV/wD/AAD/MwD/ZgD/"
        ++ "mQD/zAD//zMAADMAMzMAZjMAmTMAzDMA/zMrADMrMzMrZjMrmTMrzDMr/zNVADNVMzNVZjNVmTNVzDNV/zOAADOA"
        ++ "MzOAZjOAmTOAzDOA/zOqADOqMzOqZjOqmTOqzDOq/zPVADPVMzPVZjPVmTPVzDPV/zP/ADP/MzP/ZjP/mTP/zDP/"
        ++ "/2YAAGYAM2YAZmYAmWYAzGYA/2YrAGYrM2YrZmYrmWYrzGYr/2ZVAGZVM2ZVZmZVmWZVzGZV/2aAAGaAM2aAZmaA"
        ++ "mWaAzGaA/2aqAGaqM2aqZmaqmWaqzGaq/2bVAGbVM2bVZmbVmWbVzGbV/2b/AGb/M2b/Zmb/mWb/zGb//5kAAJkA"
        ++ "M5kAZpkAmZkAzJkA/5krAJkrM5krZpkrmZkrzJkr/5lVAJlVM5lVZplVmZlVzJlV/5mAAJmAM5mAZpmAmZmAzJmA"
        ++ "/5mqAJmqM5mqZpmqmZmqzJmq/5nVAJnVM5nVZpnVmZnVzJnV/5n/AJn/M5n/Zpn/mZn/zJn//8wAAMwAM8wAZswA"
        ++ "mcwAzMwA/8wrAMwrM8wrZswrmcwrzMwr/8xVAMxVM8xVZsxVmcxVzMxV/8yAAMyAM8yAZsyAmcyAzMyA/8yqAMyq"
        ++ "M8yqZsyqmcyqzMyq/8zVAMzVM8zVZszVmczVzMzV/8z/AMz/M8z/Zsz/mcz/zMz///8AAP8AM/8AZv8Amf8AzP8A"
        ++ "//8rAP8rM/8rZv8rmf8rzP8r//9VAP9VM/9VZv9Vmf9VzP9V//+AAP+AM/+AZv+Amf+AzP+A//+qAP+qM/+qZv+q"
        ++ "mf+qzP+q///VAP/VM//VZv/Vmf/VzP/V////AP//M///Zv//mf//zP///wAAAAAAAAAAAAAAACH5BAEAAPwALAAA"
        ++ "AAACAAEAAAgFAKWRCAgAOw==");
    defer testing.allocator.free(gif);

    var image = try imaging.decodeRgb8(testing.allocator, gif);
    defer image.deinit();

    try testing.expectEqual(@as(usize, 2), image.width);
    try testing.expectEqual(@as(usize, 1), image.height);
    try testing.expectEqual(@as(usize, 3), image.channels);
    try testing.expect(image.data[0] > image.data[1]);
    try testing.expect(image.data[0] > image.data[2]);
    try testing.expect(image.data[4] > image.data[3]);
    try testing.expect(image.data[4] > image.data[5]);
}

test "decodeRgb8 decodes interlaced png" {
    const testing = std.testing;

    const png = try helpers.decodeBase64Alloc(testing.allocator, "iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAGK06rlAAAAD0lEQVR4nGP4zwAEEAIIACDuBfv1K+nKAAAAAElFTkSuQmCC");
    defer testing.allocator.free(png);

    var image = try imaging.decodeRgb8(testing.allocator, png);
    defer image.deinit();

    try testing.expectEqual(@as(usize, 2), image.width);
    try testing.expectEqual(@as(usize, 2), image.height);
    try testing.expectEqual(@as(usize, 3), image.channels);
    try testing.expectEqualSlices(u8, &[_]u8{
        255, 0, 0,
        0, 255, 0,
        0, 0, 255,
        255, 255, 255,
    }, image.data);
}

test "decodeRgb8 decodes 2-bit grayscale png" {
    const testing = std.testing;

    const png = try helpers.decodeBase64Alloc(testing.allocator, "iVBORw0KGgoAAAANSUhEUgAAAAQAAAABAgAAAACW50iwAAAACklEQVR4nGOQBgAAHQAcjvT1IQAAAABJRU5ErkJggg==");
    defer testing.allocator.free(png);

    var image = try imaging.decodeRgb8(testing.allocator, png);
    defer image.deinit();

    try testing.expectEqual(@as(usize, 4), image.width);
    try testing.expectEqual(@as(usize, 1), image.height);
    try testing.expectEqualSlices(u8, &[_]u8{
        0, 0, 0,
        85, 85, 85,
        170, 170, 170,
        255, 255, 255,
    }, image.data);
}

test "decodeRgb8 decodes gray-alpha png" {
    const testing = std.testing;

    const png = try helpers.decodeBase64Alloc(testing.allocator, "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAQAAABeK7cBAAAADUlEQVR4nGP4/5+hAQAHfgJ/pSPAfwAAAABJRU5ErkJggg==");
    defer testing.allocator.free(png);

    var image = try imaging.decodeRgb8(testing.allocator, png);
    defer image.deinit();

    try testing.expectEqual(@as(usize, 2), image.width);
    try testing.expectEqual(@as(usize, 1), image.height);
    try testing.expectEqualSlices(u8, &[_]u8{ 255, 255, 255, 0, 0, 0 }, image.data);
}

test "decodeRgb8 decodes 4-bit palette png" {
    const testing = std.testing;

    const png = try helpers.decodeBase64Alloc(testing.allocator, "iVBORw0KGgoAAAANSUhEUgAAAAQAAAABBAMAAAALEhL+AAAADFBMVEX/AAAA/wAAAP/////7AGD2AAAAC0lEQVR4nGNgVAYAACgAJTrDFe8AAAAASUVORK5CYII=");
    defer testing.allocator.free(png);

    var image = try imaging.decodeRgb8(testing.allocator, png);
    defer image.deinit();

    try testing.expectEqual(@as(usize, 4), image.width);
    try testing.expectEqual(@as(usize, 1), image.height);
    try testing.expectEqualSlices(u8, &[_]u8{
        255, 0, 0,
        0, 255, 0,
        0, 0, 255,
        255, 255, 255,
    }, image.data);
}

test "decodeRgb8 decodes palette png" {
    const testing = std.testing;

    const png = try helpers.decodeBase64Alloc(testing.allocator, "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAMAAADD/I+4AAAABlBMVEX/AAAA/wDSh+9xAAAAC0lEQVR4nGNgYAQAAAQAAr96P0oAAAAASUVORK5CYII=");
    defer testing.allocator.free(png);

    var image = try imaging.decodeRgb8(testing.allocator, png);
    defer image.deinit();

    try testing.expectEqual(@as(usize, 2), image.width);
    try testing.expectEqual(@as(usize, 1), image.height);
    try testing.expectEqualSlices(u8, &[_]u8{ 255, 0, 0, 0, 255, 0 }, image.data);
}

test "decodeRgb8 decodes png-backed ico" {
    const testing = std.testing;

    const png_bytes = try helpers.decodeBase64Alloc(testing.allocator, "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAANSURBVBhXY/jPwPAfAAUAAf+mXJtdAAAAAElFTkSuQmCC");
    defer testing.allocator.free(png_bytes);

    const ico_len = 6 + 16 + png_bytes.len;
    const ico = try testing.allocator.alloc(u8, ico_len);
    defer testing.allocator.free(ico);

    ico[0] = 0x00;
    ico[1] = 0x00;
    ico[2] = 0x01;
    ico[3] = 0x00;
    ico[4] = 0x01;
    ico[5] = 0x00;
    ico[6] = 0x01;
    ico[7] = 0x01;
    ico[8] = 0x00;
    ico[9] = 0x00;
    ico[10] = 0x01;
    ico[11] = 0x00;
    ico[12] = 0x20;
    ico[13] = 0x00;

    helpers.writeU32le(ico[14..18], @intCast(png_bytes.len));
    helpers.writeU32le(ico[18..22], 22);
    @memcpy(ico[22..], png_bytes);

    var image = try imaging.decodeRgb8(testing.allocator, ico);
    defer image.deinit();

    try testing.expectEqual(@as(usize, 1), image.width);
    try testing.expectEqual(@as(usize, 1), image.height);
    try testing.expectEqual(@as(usize, 3), image.channels);
    try testing.expect(image.data[0] > image.data[1]);
    try testing.expect(image.data[0] > image.data[2]);
}

test "decodeRgb8 decodes bmp-backed ico" {
    const testing = std.testing;

    const payload_len: usize = 40 + 4 + 4;
    const ico_len: usize = 6 + 16 + payload_len;
    const ico = try testing.allocator.alloc(u8, ico_len);
    defer testing.allocator.free(ico);
    @memset(ico, 0);

    ico[0] = 0x00;
    ico[1] = 0x00;
    ico[2] = 0x01;
    ico[3] = 0x00;
    ico[4] = 0x01;
    ico[5] = 0x00;
    ico[6] = 0x01;
    ico[7] = 0x01;
    ico[8] = 0x00;
    ico[9] = 0x00;
    ico[10] = 0x01;
    ico[11] = 0x00;
    ico[12] = 0x20;
    ico[13] = 0x00;
    helpers.writeU32le(ico[14..18], payload_len);
    helpers.writeU32le(ico[18..22], 22);

    const dib = ico[22..];
    helpers.writeU32le(dib[0..4], 40);
    helpers.writeU32le(dib[4..8], 1);
    helpers.writeU32le(dib[8..12], 2);
    dib[12] = 0x01;
    dib[13] = 0x00;
    dib[14] = 0x20;
    dib[15] = 0x00;
    helpers.writeU32le(dib[16..20], 0);
    helpers.writeU32le(dib[20..24], 4);
    helpers.writeU32le(dib[24..28], 0);
    helpers.writeU32le(dib[28..32], 0);
    helpers.writeU32le(dib[32..36], 0);
    helpers.writeU32le(dib[36..40], 0);

    dib[40] = 0x00;
    dib[41] = 0x00;
    dib[42] = 0xff;
    dib[43] = 0xff;
    dib[44] = 0x00;
    dib[45] = 0x00;
    dib[46] = 0x00;
    dib[47] = 0x00;

    var image = try imaging.decodeRgb8(testing.allocator, ico);
    defer image.deinit();

    try testing.expectEqual(@as(usize, 1), image.width);
    try testing.expectEqual(@as(usize, 1), image.height);
    try testing.expectEqual(@as(usize, 3), image.channels);
    try testing.expect(image.data[0] > image.data[1]);
    try testing.expect(image.data[0] > image.data[2]);
}

test "decodeRgb8 handles lossy and animated webp" {
    const testing = std.testing;

    const lossy = try helpers.decodeBase64Alloc(testing.allocator, "UklGRkgAAABXRUJQVlA4IDwAAAAwAgCdASoCAAEAAAAAJaACdLoB+AADIQb7gAD5f/8uv//vTP/5zIj//2Z7/Znv9me/+zPf/maJjmP16AA=");
    defer testing.allocator.free(lossy);
    if (builtin.os.tag == .windows) {
        var image = try imaging.decodeRgb8(testing.allocator, lossy);
        defer image.deinit();

        try testing.expectEqual(@as(usize, 2), image.width);
        try testing.expectEqual(@as(usize, 1), image.height);
        try testing.expectEqual(@as(usize, 3), image.channels);
        try testing.expect(image.data[0] >= 80 and image.data[0] <= 100);
        try testing.expect(@abs(@as(i16, image.data[0]) - @as(i16, image.data[1])) <= 2);
        try testing.expect(image.data[2] <= 5);
        try testing.expect(image.data[3] > image.data[0]);
        try testing.expect(@abs(@as(i16, image.data[3]) - @as(i16, image.data[4])) <= 2);
        try testing.expect(image.data[5] >= 40 and image.data[5] <= 70);
    } else {
        try testing.expectError(error.UnsupportedWebpBitstream, imaging.decodeRgb8(testing.allocator, lossy));
    }

    const animated = try helpers.decodeBase64Alloc(testing.allocator, "UklGRsoAAABXRUJQVlA4WAoAAAACAAAAAAAAAAAAQU5JTQYAAAAAAAAAAABBTk1GSgAAAAAAAAAAAAAAAAAAAGQAAAJWUDggMgAAADABAJ0BKgEAAQABQCYloAADcAD+8ut///mwP/bz/wR6Af//0uD//pcH//S4P/SkAAAAQU5NRkwAAAAAAAAAAAAAAAAAAABkAAAAVlA4IDQAAAA0AQCdASoBAAEAAAAmJaAAA3AA/ukiH//3nz//ufP/+58/6M///yn7//I4//8jj/5QIAAA");
    defer testing.allocator.free(animated);
    try testing.expectError(error.UnsupportedWebpAnimation, imaging.decodeRgb8(testing.allocator, animated));
}

test "decodeRgba8 preserves png transparency" {
    const testing = std.testing;

    const png = try helpers.decodeBase64Alloc(testing.allocator, "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABAQAAAAA3bvkkAAAAAnRSTlMAAQGU/a4AAAAKSURBVHicY2gAAACCAIF3zXK2AAAAAElFTkSuQmCC");
    defer testing.allocator.free(png);

    var image = try imaging.decodeRgba8(testing.allocator, png);
    defer image.deinit();

    try testing.expectEqual(@as(usize, 1), image.width);
    try testing.expectEqual(@as(usize, 1), image.height);
    try testing.expectEqual(@as(usize, 4), image.channels);
    try testing.expectEqual(@as(u8, 0), image.data[3]);
}

test "decodeReaderRgba8 reads from std.Io.Reader" {
    const testing = std.testing;

    const png = try helpers.decodeBase64Alloc(testing.allocator, "iVBORw0KGgoAAAANSUhEUgAAAAIAAAABCAQAAABeK7cBAAAADUlEQVR4nGP4/5+hAQAHfgJ/pSPAfwAAAABJRU5ErkJggg==");
    defer testing.allocator.free(png);

    var reader = std.Io.Reader.fixed(png);
    var image = try imaging.decodeReaderRgba8(testing.allocator, &reader);
    defer image.deinit();

    try testing.expectEqual(@as(usize, 2), image.width);
    try testing.expectEqual(@as(usize, 1), image.height);
    try testing.expectEqual(@as(usize, 4), image.channels);
    try testing.expectEqualSlices(u8, &[_]u8{ 255, 255, 255, 255, 0, 0, 0, 128 }, image.data);
}

test "decodeFileRgba8 decodes bmp alpha without loading via byte slice API" {
    const testing = std.testing;

    const path = "._pixio_rgba32.bmp";
    defer std.fs.cwd().deleteFile(path) catch {};

    var bmp = [_]u8{
        0x42, 0x4d, 0x3e, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x36, 0x00, 0x00, 0x00,
        0x28, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x00,
        0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x08, 0x00, 0x00, 0x00, 0x13, 0x0b, 0x00, 0x00,
        0x13, 0x0b, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0xff, 0x40, 0x00, 0xff, 0x00, 0xff,
    };
    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = &bmp });

    var image = try imaging.decodeFileRgba8(testing.allocator, path);
    defer image.deinit();

    try testing.expectEqual(@as(usize, 2), image.width);
    try testing.expectEqual(@as(usize, 1), image.height);
    try testing.expectEqual(@as(usize, 4), image.channels);
    try testing.expectEqualSlices(u8, &[_]u8{
        255, 0, 0, 64,
        0, 255, 0, 255,
    }, image.data);
}
