# Zarr slice → mizchi/image PNG

This author-maintained integration encodes RGBA slices exported by the volume
application with the published `mizchi/image@0.5.0` PNG encoder. It demonstrates
a usable connection between two MoonBit libraries, not an external adoption.

The modules deliberately run in separate processes: image's zlib dependency
requires async 0.22.4, while Zarr 0.10.0 uses async 0.20.3. A direct combined
module selects the newer async and fails on Zarr's `resume_on_cancel` labels.
The explicit bridge avoids a runtime migration for this demo.

The bridge format is tightly packed row-major RGBA8, four bytes per pixel,
opaque alpha, no header. The exporter reads a normalized float32 Zarr plane,
maps each value with `floor(value*255+0.5)`, and preserves array row/column order.
There is no physical-coordinate interpretation or color management. Both
dimensions are limited to 2048. Files must be new.

From the repository root, after completing a conversion:

```sh
moon run --target native examples/volume_pipeline --check /absolute/output.zarr
moon run --target native examples/volume_pipeline --export-slice /absolute/output.zarr 64 /absolute/slice.rgba
moon run --target native examples/zarr_preview /absolute/slice.rgba 128 128 /absolute/slice.png
```

Use the actual plane and dimensions for the selected output. A root `moon.work`
must not be present when building the independent preview module. For a
single command that handles the paths and independently validates every PNG
pixel, see [SHOWCASE.md](../../docs/SHOWCASE.md).

Zarr and this example are Apache-2.0; the external image and zlib packages also
declare Apache-2.0. Their code is downloaded as dependencies, not copied here.
