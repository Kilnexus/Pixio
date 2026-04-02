const std = @import("std");
const c = @cImport({
    @cInclude("objbase.h");
    @cInclude("wincodec.h");
});
const types = @import("types.zig");

pub const ImageU8 = types.ImageU8;

pub fn decodeContainerRgb8(allocator: std.mem.Allocator, bytes: []const u8) !ImageU8 {
    return decodeContainerWithFormat(allocator, bytes, &c.GUID_WICPixelFormat24bppRGB, 3);
}

pub fn decodeContainerRgba8(allocator: std.mem.Allocator, bytes: []const u8) !ImageU8 {
    return decodeContainerWithFormat(allocator, bytes, &c.GUID_WICPixelFormat32bppRGBA, 4);
}

fn decodeContainerWithFormat(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    pixel_format: *const c.GUID,
    channels: usize,
) !ImageU8 {
    const init_hr = c.CoInitializeEx(null, c.COINIT_MULTITHREADED);
    const should_uninit = init_hr >= 0;
    if (hrFailed(init_hr) and init_hr != c.RPC_E_CHANGED_MODE) return error.UnsupportedWebpBitstream;
    defer if (should_uninit) c.CoUninitialize();

    var factory: ?*c.IWICImagingFactory = null;
    if (hrFailed(c.CoCreateInstance(
        &c.CLSID_WICImagingFactory,
        null,
        c.CLSCTX_INPROC_SERVER,
        &c.IID_IWICImagingFactory,
        @ptrCast(&factory),
    ))) return error.UnsupportedWebpBitstream;
    defer release(factory);

    var stream: ?*c.IWICStream = null;
    if (hrFailed(factory.?.lpVtbl.*.CreateStream.?(factory, &stream))) return error.InvalidWebpData;
    defer release(stream);

    if (hrFailed(stream.?.lpVtbl.*.InitializeFromMemory.?(stream, @constCast(bytes.ptr), @intCast(bytes.len)))) {
        return error.InvalidWebpData;
    }

    var decoder: ?*c.IWICBitmapDecoder = null;
    if (hrFailed(factory.?.lpVtbl.*.CreateDecoderFromStream.?(
        factory,
        @ptrCast(stream),
        null,
        c.WICDecodeMetadataCacheOnLoad,
        &decoder,
    ))) return error.UnsupportedWebpBitstream;
    defer release(decoder);

    var frame: ?*c.IWICBitmapFrameDecode = null;
    if (hrFailed(decoder.?.lpVtbl.*.GetFrame.?(decoder, 0, &frame))) return error.InvalidWebpData;
    defer release(frame);

    var converter: ?*c.IWICFormatConverter = null;
    if (hrFailed(factory.?.lpVtbl.*.CreateFormatConverter.?(factory, &converter))) return error.InvalidWebpData;
    defer release(converter);

    if (hrFailed(converter.?.lpVtbl.*.Initialize.?(
        converter,
        @ptrCast(frame),
        pixel_format,
        c.WICBitmapDitherTypeNone,
        null,
        0.0,
        c.WICBitmapPaletteTypeCustom,
    ))) return error.InvalidWebpData;

    var width: c.UINT = 0;
    var height: c.UINT = 0;
    if (hrFailed(converter.?.lpVtbl.*.GetSize.?(@ptrCast(converter), &width, &height))) return error.InvalidWebpData;
    if (width == 0 or height == 0) return error.InvalidWebpData;

    var image = try ImageU8.init(allocator, width, height, channels);
    errdefer image.deinit();

    const stride = image.width * image.channels;
    if (hrFailed(converter.?.lpVtbl.*.CopyPixels.?(
        @ptrCast(converter),
        null,
        @intCast(stride),
        @intCast(image.data.len),
        image.data.ptr,
    ))) return error.InvalidWebpData;

    return image;
}

fn hrFailed(hr: c.HRESULT) bool {
    return hr < 0;
}

fn release(ptr: anytype) void {
    _ = ptr.?.lpVtbl.*.Release.?(@ptrCast(ptr));
}
