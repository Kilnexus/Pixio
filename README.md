# Pixio

`Pixio` is a standalone Zig imaging package extracted from Axionyx for reuse in other projects.

## Features

- Image decode to RGB8: PNG, BMP, JPEG, GIF, ICO, WebP
- Format probe and metadata inspection
- WebP lossless inspection helpers
- Bilinear resize
- Letterbox utilities
- Box remap helpers (letterboxed image -> source coordinates)

## Build

```bash
zig build test
```

## Package Import (build.zig)

```zig
const pixio_dep = b.dependency("pixio", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("pixio", pixio_dep.module("pixio"));
```

## Basic Usage

```zig
const pixio = @import("pixio");
```
