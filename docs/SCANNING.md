# Typed tile readers

Since 0.9.0, readers combine `RegionTileCursor` with typed reads. They pull one tile per `next()` call and return `Result[Tile[T]?, store.AccessError]`. `Tile` contains `origin`, `extent` and C-ordered `values`. Tile visitation follows the planner's C order; concatenating tile values does **not** generally reconstruct a whole C-ordered region. Use the coordinates when placing tiles into an output array.

| Package | Source | Backend |
|---|---|---|
| `scan.Reader[T]` | Synchronous typed-read callback, including memory arrays | native / wasm-gc |
| `scan/async.Reader[T]` | Async typed-read callback, including filesystem arrays | native |
| `scan/remote.Source` | HTTP/S3 hydration plus typed decoding | native |

Existing element/region APIs and the coordinate-only planner remain available. No store writes, prefetch or parallel processing are introduced.

## Automatic HTTP and S3 reads

For a fresh native executable, install `zlhahaha/zarr@0.9.0` and a direct `moonbitlang/async@0.20.3` dependency. Its `moon.pkg` is:

```moonbit
import {
  "zlhahaha/zarr/store/s3",
  "zlhahaha/zarr/scan/remote",
  "moonbitlang/async",
}
pkgtype(kind: "executable")
supported_targets = "native"
```

`main.mbt` reads a fixed public 3D data selection and computes a histogram without collecting its tiles:

```moonbit
async fn main {
  guard @s3.S3Store::new(
      "ome-zarr-scivis", "us-east-1",
      prefix="v0.4/64x0/bonsai.ome.zarr",
    ) is Some(store) else { abort("store configuration") }
  guard @remote.Source::s3(store).open_u8(
      "scale0/bonsai", [0, 0, 0], [128, 128, 128], [64, 64, 64],
    ) is Ok(reader) else { abort("array metadata/selection") }
  let histogram = Array::make(256, 0)
  while true {
    match reader.next() {
      Ok(Some(tile)) => for value in tile.values {
        histogram[value.to_int()] += 1
      }
      Ok(None) => break
      Err(_) => abort("remote tile read/decode failed")
    }
  }
  let mut voxels = 0
  let mut sum = 0L
  for i in 0..<256 {
    voxels += histogram[i]
    sum += histogram[i].to_int64() * i.to_int64()
  }
  if voxels != 2097152 || sum != 24039966L { abort("checksum") }
  println("OME-Zarr histogram: 2097152 voxels, checksum=24039966")
}
```

For HTTP, construct `http.HttpStore::new(base_url, ...)` and wrap it with `Source::http(store)`. Configuration stays on the existing store: resource policies, timeout, cache and authentication all apply. For authenticated S3 use explicitly supplied credentials as described in [REMOTE.md](REMOTE.md). Known array paths require GET access, not bucket-list permission.

Built-in `Source::open_u8`, `open_u16` and `open_f32` cover image intensities, volumes and feature tensors. Generic `Source::open` accepts a decoder `(MemoryStore, String, RegionTile) -> Array[T]?` for other existing numeric dtypes; open the typed memory view and read its tile inside that callback. `open_u8` converts the existing `Bytes` region result into `Array[Byte]` for the common typed interface; that conversion can allocate a copy.

`open` fetches validated shape metadata and constructs a plan. It does not fetch payloads; dtype/codec/payload decoding is checked when a tile is pulled. A wrong dtype or malformed decoded payload yields `Protocol(path, "typed tile decode rejected")`, rather than a missing-fill result. Transport, authentication and hydration errors preserve the existing `AccessError`. An empty selection never invokes the decoder. The scan is not a snapshot across changing remote metadata/objects.

## Memory and filesystem callbacks

For any memory typed array, construct `scan.Reader::new(shape, origin, extent, tile_shape, callback)`. The callback calls `array.read_region(tile.origin, tile.extent)` and maps `Some(values)` to `Ok(values)` or `None` to an appropriate `AccessError`. Convert `Bytes` with `to_array()` for uint8. The executable [tile demo](../cmd/tile_demo/main.mbt) scans a logical 256 MiB sparse array this way.

The native async constructor has the same arguments and an async callback. For example, with an already opened `FileStore` uint16 array:

```moonbit
guard @reader.Reader::new(shape, origin, extent, tile_shape, tile => {
    match array.read_region(tile.origin, tile.extent) {
      Some(values) => Ok(values)
      None => Err(@store.InvalidRegion("volume"))
    }
  }) is Some(reader) else { abort("invalid tile plan") }
```

Import `zlhahaha/zarr/scan/async` as `@reader` and `zlhahaha/zarr/store` as `@store`. This callback works for other native typed arrays too. Native filesystem exceptions still propagate from the callback; use the exception handling in [USAGE.md](USAGE.md). The [N-D demo](../cmd/nd_demo/main.mbt) reads nonaligned tiles from a compressed filesystem volume and verifies all coordinates and values.

## Lifecycle and limits

- `new` returns `None` for invalid geometry or an exceeded `max_tile_elements` (default 8,388,608). Remote `open` reports `InvalidRegion` for the same plan rejection.
- Scalar selections yield one scalar tile; empty selections yield none. Edge tiles are clipped to the requested region.
- Each successful result has exactly the product of its extent in elements. A callback returning the wrong count becomes a terminal `Protocol` error. Descriptor coordinates are copied before application callbacks run.
- `Ok(None)` means exhausted or explicitly closed. Ordinary `Err` is sticky: calling `next()` again returns the same error without skipping the failed tile or making another request. Recreate a reader to restart; retries belong to the underlying transport policy.
- `close()` releases the callback and performs no more reads. During an async call it allows that call to finish but prevents subsequent calls. Do not use simultaneous `next()` calls: a second call returns `Protocol("tile", "concurrent next")` while the active call proceeds.
- Async callback exceptions/cancellation propagate. The reader then remains terminal: subsequent calls return `Io("tile callback aborted")`, with no resumed traversal. `close()` does not cancel an in-flight operation; cancellation belongs to the caller's task.
- No prior yielded tile values are retained by the reader. A consumer retaining them will accumulate memory. Each tile still buffers its result and decoded chunks; transport caches and runtime allocations also occupy memory. `max_tile_elements` and `ReadLimits` are **not aggregate-RAM guarantees**. Choose small tiles, usually chunk-aligned, and consume/discard them sequentially.

Run `moon run --target native cmd/nd_demo` and `moon run --target native cmd/tile_demo`; the latter also runs on wasm-gc. The optional public-network example is `moon run --target native cmd/real_bonsai --volume`. See [real-data benchmark](REAL_DATA_BENCHMARK.md) for independently checked statistics and actual process peak RSS.
