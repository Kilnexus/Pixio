# Pixio

`Pixio` is a standalone Zig imaging package extracted from Axionyx for reuse in other projects.

## Features

- Image decode to RGB8 with explicit format constraints
- Format probe and metadata inspection
- WebP lossless inspection helpers
- Bilinear resize
- Letterbox utilities
- Box remap helpers (letterboxed image -> source coordinates)

## Decode Support Matrix

All decoders return RGB8 output. Alpha is reported by probe APIs where available but is not preserved in decode output.

| Format | Decode support | Notes |
| --- | --- | --- |
| PNG | Partial | 1/2/4/8-bit grayscale and palette, plus 8-bit gray+alpha, RGB, RGBA; supports standard and Adam7 interlaced images; probe reports `tRNS` alpha |
| BMP | Partial | Uncompressed 8-bit palette, 24-bit, and 32-bit BMP |
| JPEG | Partial | Baseline and progressive 8-bit JPEG; grayscale or 3-component scans |
| GIF | Partial | Palette GIF decode of the first image frame |
| ICO | Partial | PNG-backed icons and BMP-backed 24-bit/32-bit icons |
| WebP | Partial | Lossless VP8L decode everywhere; lossy VP8 decode via Windows WIC; VP8X animation decode is not implemented |

## Probe Support

`probeInfo` is a metadata-oriented shallow probe. It returns width, height, RGB channel count, and alpha presence for PNG, BMP, JPEG, GIF, ICO, and WebP, and it may succeed for files that the current decoders still reject, such as animated WebP.

`probeFileInfo` and `probeWebpFileInfo` avoid reading entire files into memory. They read fixed-layout headers directly and scan JPEG/WebP containers incrementally.

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
