# Zarr

[![CI](https://github.com/zlhahaha/zarr/actions/workflows/ci.yml/badge.svg)](https://github.com/zlhahaha/zarr/actions/workflows/ci.yml)

A MoonBit implementation of the Zarr v2 and v3 storage formats for chunked N-dimensional arrays. This is an independent implementation, not an official Zarr Developers project.

## Status

Early development. The library can read and write `bool`, signed/unsigned 8/16/32/64-bit integers, and `float32`/`float64` arrays in memory and on native filesystems, including element access, rectangular slices, missing-chunk fill values and edge chunks. It supports raw chunks and gzip/zstd in both formats, plus zlib in v2. Groups and attributes can be read and written for both formats. A native-only HTTP adapter can download the metadata and encoded chunks touched by a bounded rectangle into a `MemoryStore`; it is read-only and has no persistent cache. Rectangular slices batch file I/O and codec work by touched chunk, but still buffer the requested result and are not a streaming typed-array interface. Other dtypes/codecs and cloud object-store adapters are not implemented yet. Do not use it as a general Zarr reader/writer yet.

Float32/float64 fill values also support the standard JSON strings `"NaN"`, `"Infinity"`, and `"-Infinity"`. Creating an array with any NaN writes the canonical `"NaN"` fill value; v3 payload-specific hexadecimal NaN fills are not supported.

| Capability | Zarr v2 | Zarr v3 |
| --- | --- | --- |
| Parse regular-grid array metadata | Yes, common string dtypes | Yes, common string data types |
| Metadata and chunk keys | `.` and `/` separators | default and v2-compatible encodings |
| Raw encoded chunk storage | Memory and native filesystem | Memory and native filesystem |
| `bool` element and slice I/O | Memory and native filesystem | Memory and native filesystem; bytes codec |
| `uint8` element I/O | Memory and native filesystem; C/F order | Memory and native filesystem; bytes codec |
| `int8` element and slice I/O (`Int` API, range-checked) | Memory and native filesystem; C/F order | Memory and native filesystem; bytes codec |
| `uint16` element and slice I/O | Memory and native filesystem; little/big endian, C/F order | Memory and native filesystem; little/big endian bytes codec |
| `int16` element and slice I/O | Memory and native filesystem; little/big endian, C/F order | Memory and native filesystem; little/big endian bytes codec |
| `uint32` element and slice I/O | Memory and native filesystem; little/big endian, C/F order | Memory and native filesystem; little/big endian bytes codec |
| `float64` element I/O | Memory and native filesystem; little/big endian, C/F order | Memory and native filesystem; little/big endian bytes codec |
| `float32` element I/O | Memory and native filesystem; little/big endian, C/F order | Memory and native filesystem; little/big endian bytes codec |
| `int32` element I/O | Memory and native filesystem; little/big endian, C/F order | Memory and native filesystem; little/big endian bytes codec |
| `int64` element and slice I/O | Memory and native filesystem; little/big endian, C/F order | Memory and native filesystem; little/big endian bytes codec |
| `uint64` element and slice I/O | Memory and native filesystem; little/big endian, C/F order | Memory and native filesystem; little/big endian bytes codec |
| Rectangular slice I/O (all listed types) | Memory and native filesystem | Memory and native filesystem |
| gzip compression (levels 0–9) | Read/write | Read/write after bytes codec |
| zstd compression (levels 0–22) | Read/write | Read/write after bytes codec, checksum=false |
| zlib compression (levels 0–9) | Read/write | Not a v3 core codec |
| Other dtypes, filters and codecs | Planned | Planned |
| Groups, ancestors and attributes | Memory and native filesystem (`.zgroup`/`.zattrs`) | Memory and native filesystem (`zarr.json`) |
| Consolidated metadata | Read-only native `.zmetadata` snapshot | Read-only native inline root `zarr.json` snapshot (zarr-python convention) |
| HTTP read-only regional hydration | Native, bounded metadata/chunk downloads | Native, bounded metadata/chunk downloads |
| Cloud object-store adapters | Planned | Planned |

## Build and run

Requires the MoonBit toolchain. CI checks native builds and tests on Linux, macOS and Windows, plus wasm-gc on Linux; release packaging and Python interoperability run on Linux. The library also passes local checks with the July 2026 toolchain. From this directory:

```sh
moon check --deny-warn
moon build
moon test --deny-warn
moon run cmd/main
moon test --target native --deny-warn
moon run --target native cmd/native_demo
moon run --target native cmd/v2_demo
```

The example creates a v3 `uint8` array and writes a slice across chunks. It prints `Zarr v3 uint8 values: 0,7,9,11`.
The first native example creates and reopens a v3 zstd-compressed `uint16` array in a temporary filesystem store. The v2 example does the same with a gzip-compressed, big-endian `int16` array and verifies a rectangular read after reopening. All examples exit with an error if their checks fail. See [docs/USAGE.md](docs/USAGE.md) for the public API and format limits.

## Interoperability tests

Native tests read twenty-eight committed v2/v3 sample stores generated by zarr-python 3.4.0, covering numeric and boolean types, signed bytes, full-range 64-bit integers, non-finite floating fills, gzip/zlib/zstd, nested groups and both consolidated-metadata conventions. The generators include [scripts/generate_v3_consolidated_fixture.py](scripts/generate_v3_consolidated_fixture.py) alongside the other scripts listed in [the fixture inventory](integration/fixtures/zarr-python/README.md). In the reverse direction, the `cmd/interop`, `cmd/nonfinite_interop`, `cmd/int64_interop`, and `cmd/int8_interop` generators write twenty-seven stores—including a multi-chunk compressed slice, boolean masks, non-finite fills, full-range 64-bit integers, signed bytes and v2/v3 nested groups—to the ignored `integration/.roundtrip/` directory, and [scripts/verify_moonbit_roundtrip.py](scripts/verify_moonbit_roundtrip.py) opens them with zarr-python. CI installs the pinned Python test oracle and runs both directions. The generators refuse to overwrite existing stores; remove only their generated directories before re-running locally.

## Design

Both formats share a storage-neutral array API, but retain their distinct metadata, chunk-key, dtype, and codec rules. Unknown or unsupported encodings must fail explicitly instead of returning incorrect values. The MoonBit packages follow one-way dependencies:

```text
metadata/        Parse and validate v2/v3 array and group documents
chunk/           Regular-grid indexing and metadata/chunk keys
dtype/           Numeric dtype and fill-value checks
codec/           Codec-chain validation and bounded gzip/zlib/zstd decode
store/           In-memory encoded-byte store
store/fs/        Native-only filesystem store
store/http/      Native-only read-only HTTP regional hydration
array/           Typed array creation, element and region I/O
hierarchy/       Group and attribute operations
integration/     Cross-package tests
cmd/main/        Portable in-memory v3 example
cmd/native_demo/ Native filesystem v3 example
cmd/v2_demo/     Native filesystem v2 example
```

The public array functions live in `zlhahaha/zarr/array`; `MemoryStore` lives in `zlhahaha/zarr/store`, and format constants in `zlhahaha/zarr/metadata`. For example, `@array.create_u8(store, @metadata.V3, "samples", [4], [2], b'\x00', compression=@codec.Zstd(3))` creates a compressed v3 array without hand-writing metadata JSON. On native, `FileStore::create_u8` accepts the same `compression` option. gzip/zlib output is bounded while decoding; zstd frames are preflight-checked against the declared chunk size using the dependency's frame-size bound. Thus, valid zstd frames without a known content size may be rejected if the conservative bound exceeds the chunk size. See [the roadmap](docs/ROADMAP.md) for the staged interoperability targets.

## Specification and attribution

This project implements the publicly documented [Zarr v2 storage specification](https://zarr-specs.readthedocs.io/en/latest/v2/v2.0.html) and [Zarr v3 core specification](https://zarr-specs.readthedocs.io/en/latest/v3/core/). The [Zarr specifications repository](https://github.com/zarr-developers/zarr-specs) is CC BY 4.0. No upstream implementation code was copied. The committed interoperability stores were generated by this repository's original scripts using [zarr-python 3.4.0](https://github.com/zarr-developers/zarr-python), which is MIT-licensed; see [integration/fixtures/zarr-python/README.md](integration/fixtures/zarr-python/README.md). Compression uses the Apache-2.0 MoonBit dependencies [moonbit-community/flate](https://mooncakes.io/docs/moonbit-community/flate) and [Milky2018/zstd](https://mooncakes.io/docs/Milky2018/zstd).

This project is licensed under Apache-2.0; see [LICENSE](LICENSE).
