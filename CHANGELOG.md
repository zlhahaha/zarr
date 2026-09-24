# Changelog

## 0.1.0 — Source preview, not published to Mooncakes

Initial interoperable subset of Zarr storage formats 2 and 3 for MoonBit.

- Read and write regular-grid arrays of `bool`, signed/unsigned 8/16/32/64-bit integers, and `float32`/`float64` in memory and on native filesystems, including element access, rectangular regions, edge chunks, and missing-chunk fill values. Full-range 64-bit integer fills retain exact JSON representation; `int8` uses range-checked `Int` values.
- Encode and decode canonical `NaN` and positive/negative infinity fills for float32/float64 in both formats.
- Read and write v2 and v3 groups and attributes; read v2 consolidated metadata as a read-only native snapshot.
- Read zarr-python's v3 inline consolidated metadata from a read-only native snapshot.
- Support raw, gzip, and zstd chunks in both formats, plus v2 zlib; v3 Zstd frame checksums can be read and written. Unsupported codecs and filters fail explicitly.
- Hydrate a bounded region of a static HTTP-served array into a `MemoryStore` on native targets. The read-only adapter has a configurable bounded in-memory LRU cache; it has no disk cache.
- Verify interoperability in both directions with zarr-python 3.4.0, and run native CI on Linux, macOS, and Windows plus wasm-gc CI on Linux.

See the [support table](README.md#status) and [known limits](docs/USAGE.md#supported-format-subset) before using this pre-release version.
