# Pixio

`Pixio` is a standalone Zig imaging package extracted from Axionyx for reuse in other projects.

## Features

- Image decode to RGB8 with explicit format constraints
- Optional decode to RGBA8 with alpha preservation where supported
- Format probe and metadata inspection
- WebP lossless inspection helpers
- Core image metadata types (`PixelFormat`, `ColorSpace`, `AlphaMode`, views/layout)
- PNG encode for `gray8` / `rgb8` / `rgba8`
- JPEG encode for `gray8` / `rgb8` / `rgba8` with quality control
- Pixel-format conversion between `gray8` / `rgb8` / `rgba8`
- RGBA premultiply / unpremultiply and alpha-over compositing
- Nearest, bilinear, area, bicubic, and Lanczos3 resize
- Crop and aspect-fill cover resize
- Pad, flip, and 90-degree rotation helpers
- Letterbox utilities
- Box remap helpers (letterboxed/covered image -> source coordinates)
- Float32 CHW tensor packing with normalization options

## Decode Support Matrix

`decodeRgb8` returns RGB8 output. `decodeRgba8` returns RGBA8 output and preserves alpha for PNG, BMP 32-bit, transparent GIF first frames, ICO, and WebP where the source bitstream exposes it. JPEG decode remains opaque.

| Format | Decode support | Notes |
| --- | --- | --- |
| PNG | Partial | 1/2/4/8-bit grayscale and palette, plus 8-bit gray+alpha, RGB, RGBA; supports standard and Adam7 interlaced images; probe reports `tRNS` alpha |
| BMP | Partial | Uncompressed 8-bit palette, 24-bit, and 32-bit BMP |
| JPEG | Partial | Baseline and progressive 8-bit JPEG; grayscale or 3-component scans |
| GIF | Partial | Palette GIF decode of the first image frame |
| ICO | Partial | PNG-backed icons and BMP-backed 24-bit/32-bit icons |
| WebP | Partial | Lossless VP8L decode everywhere; lossy VP8 decode via Windows WIC; VP8X animation decode is not implemented |

## Probe Support

`probeInfo` is a metadata-oriented shallow probe. It returns width, height, default decode channel count, `native_channels`, and alpha presence for PNG, BMP, JPEG, GIF, ICO, and WebP, and it may succeed for files that the current decoders still reject, such as animated WebP.

`probeFileInfo` and `probeWebpFileInfo` avoid reading entire files into memory. They read fixed-layout headers directly and scan JPEG/WebP containers incrementally.

`channels` is aligned with the default `decodeRgb8` output and is therefore always `3` for supported formats. `native_channels` reports the source image's expanded color model, for example grayscale JPEG as `1` or PNG/WebP with alpha as `4`.

## Build

```bash
zig build test
```

## Package Import (build.zig)

```zig
const pixio_dep = b.dependency("Pixio", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("Pixio", pixio_dep.module("Pixio"));
```

## Basic Usage

```zig
const pixio = @import("Pixio");
```

```zig
var rgb = try pixio.decodeRgb8(allocator, bytes);
defer rgb.deinit();

var rgba = try pixio.decodeRgba8(allocator, bytes);
defer rgba.deinit();

var cropped = try pixio.cropImage(allocator, &rgba, 32, 32, 256, 256);
defer cropped.deinit();

var covered = try pixio.coverImage(allocator, &cropped, 224, 224);
defer covered.deinit();

var tensor = try pixio.imageToTensorChwF32(allocator, &covered.image, .{
    .mean = &[_]f32{ 0.485, 0.456, 0.406 },
    .std = &[_]f32{ 0.229, 0.224, 0.225 },
});
defer tensor.deinit();

const view = try pixio.constImageView(&rgba);
const descriptor = view.layout.descriptor;
_ = descriptor.pixel_format;

var composite_ready = try pixio.convertToRgba8(allocator, &cropped);
defer composite_ready.deinit();

var premultiplied = try pixio.premultiplyRgba8(allocator, &composite_ready);
defer premultiplied.deinit();

const encoded_png = try pixio.encodePngAlloc(allocator, &rgba);
defer allocator.free(encoded_png);

const encoded_jpeg = try pixio.encodeJpegAlloc(allocator, &cropped, .{ .quality = 92 });
defer allocator.free(encoded_jpeg);
```
