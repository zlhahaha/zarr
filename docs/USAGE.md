# Using Zarr from MoonBit

This library is still pre-release. Build it locally with MoonBit; the Mooncakes installation command will be added after publication. The module name is `zlhahaha/zarr`.

## Packages

| Package | Purpose |
| --- | --- |
| `zlhahaha/zarr/metadata` | v2/v3 formats and parsed metadata |
| `zlhahaha/zarr/store` | In-memory encoded-byte store |
| `zlhahaha/zarr/store/fs` | Native filesystem store and typed arrays |
| `zlhahaha/zarr/store/http` | Native-only HTTP read-only regional hydration |
| `zlhahaha/zarr/array` | In-memory typed arrays and creation helpers |
| `zlhahaha/zarr/codec` | Compression choices (`Raw`, `Gzip`, `Zlib`, `Zstd`) |
| `zlhahaha/zarr/hierarchy` | In-memory group and attribute operations |

The repository contains three executable examples. Run `moon run --target wasm-gc cmd/main` for a portable in-memory v3 array, `moon run --target native cmd/native_demo` for a zstd-compressed v3 array on disk, or `moon run --target native cmd/v2_demo` for a gzip-compressed, big-endian v2 array on disk. Both native examples create a temporary store, reopen it, verify a slice, and remove the temporary store. Each example exits unsuccessfully if a check fails.

## Native array example

Add these imports to a native package's `moon.pkg`:

```text
import {
  "zlhahaha/zarr/metadata",
  "zlhahaha/zarr/codec",
  "zlhahaha/zarr/store/fs",
  "moonbitlang/async",
}
supported_targets = "native"
```

Then use the typed API inside an `async` function:

```moonbit
guard @fs.FileStore::new("data.zarr") is Some(store) else { return }
if !store.create_group_tree(@metadata.V3, "") { return }
guard store.create_u16(
    @metadata.V3, "pixels", [100, 200], [32, 32], (0 : UInt16),
    compression=@codec.Zstd(3),
  ) is Some(pixels) else { return }
let _ = pixels.write_region(
  [10, 20], [1, 3],
  [(100 : UInt16), (200 : UInt16), (300 : UInt16)],
)
```

`create_bool`, `create_u8`, `create_u16`, `create_i16`, `create_u32`, `create_i32`, `create_u64`, `create_i64`, `create_f32`, and `create_f64` exist on `FileStore`; matching functions accept a `MemoryStore` in the `array` package. Create a root group before adding named arrays so other Zarr readers can traverse the hierarchy. For deeper paths, `store.create_group_tree(@metadata.V3, "science/run")` creates missing ancestors without overwriting existing groups; use `@hierarchy.create_group_tree` with a `MemoryStore`. Omit `compression` for raw chunks. `Gzip(level)` works with v2/v3, `Zlib(level)` with v2 only, and `Zstd(level)` with v2/v3. `big_endian=true` is available for multi-byte types. The same typed API opens existing arrays with `store.open_u16("pixels")` and supports `read`, `write`, `read_region`, and `write_region`.

The first argument to region operations is the zero-based origin, the second is the extent. Values are in C order regardless of a v2 array's on-disk C/F chunk order. A missing chunk reads as the declared fill value; writing creates a full-sized chunk, including at array edges.

For a Zarr v2 hierarchy with `.zmetadata`, `FileStore::open_consolidated("data.zarr")` returns a read-only snapshot. This index is a zarr-python convention, not part of the v2 core storage specification. Its array and group metadata and attributes come exclusively from the consolidated index, while chunks still come from the filesystem. It can read hierarchies even when individual `.zarray`, `.zgroup`, and `.zattrs` files are absent. Writes through this view return `false`; reopen it after the index changes. Use `FileStore::new` for ordinary mutable stores.

For a static HTTP-served v2 or v3 hierarchy, the native-only `store/http` package can fetch just the metadata and chunks touched by a rectangle:

```moonbit
guard @http.HttpStore::new("https://example.org/data.zarr") is Some(remote) else { return }
guard remote.hydrate_region("science/image", [10, 20], [1, 3]) is Some(cache) else { return }
guard @array.open_u8(cache, "science/image") is Some(image) else { return }
let values = image.read_region([10, 20], [1, 3])
```

Import `zlhahaha/zarr/store/http` as `@http` and `zlhahaha/zarr/array` as `@array`. Hydration is read-only and returns a `MemoryStore`; changing it does not update the remote store. A 404 chunk is treated as the declared fill value, while non-200 responses and transport errors fail. The default caps are 1 MiB per metadata document, 64 MiB per encoded chunk and 1024 chunks per call; `HttpStore::new` accepts `max_metadata_bytes`, `max_chunk_bytes`, and `max_chunks` overrides. This is not yet an HTTP-backed typed array or persistent chunk cache.

## Supported format subset

Both formats support regular chunk grids, safe logical paths, groups and attributes, boolean arrays and the nine numeric types above. v2 supports `.`/`/` chunk separators and C/F chunk order; v3 supports default and v2-compatible chunk keys plus the bytes serializer. Raw, gzip and zstd chunks are supported in both formats; zlib is supported in v2. Unsupported filters, storage transformers and codec chains are rejected rather than silently decoded incorrectly. Full-range `int64`/`uint64` fill values are preserved as exact JSON integers rather than rounded through floating point.

The API returns `None` or `false` for invalid metadata, unsupported encodings, out-of-bounds coordinates, corrupt chunks, and I/O failures. A region write spanning multiple chunks is **not atomic**: if a later chunk fails, earlier chunks may already be saved. Large reads and writes still buffer the requested region. A `FileStore` uses native async filesystem APIs and is not available on wasm-gc; `MemoryStore` works on the tested native and wasm-gc targets.

Zstd decoding first checks the dependency's conservative frame-size bound against the declared uncompressed chunk length. Consequently, a valid frame without known content size may be rejected. v3 zstd `checksum=true`, Blosc, sharding, v3 consolidated metadata, HTTP write access, cloud object-store adapters, additional dtypes, and general ndarray arithmetic are not implemented yet. See [ROADMAP.md](ROADMAP.md) and the [support table](../README.md#status).

For floating-point arrays, `"NaN"`, `"Infinity"`, and `"-Infinity"` metadata fill values are accepted in both formats. Array creation serializes a NaN fill as the canonical `"NaN"` string. Hexadecimal NaN payload encodings from the v3 data-type specification are not yet supported.
