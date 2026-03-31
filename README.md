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
