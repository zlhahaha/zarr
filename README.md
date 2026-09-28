# Zarr

[![CI](https://github.com/zlhahaha/zarr/actions/workflows/ci.yml/badge.svg)](https://github.com/zlhahaha/zarr/actions/workflows/ci.yml)

A MoonBit implementation of the Zarr v2 and v3 storage formats for chunked N-dimensional arrays. This is an independent implementation, not an official Zarr Developers project.

## Status

Early Mooncakes release (version `0.2.0`). The library can read and write `bool`, signed/unsigned 8/16/32/64-bit integers, and `float32`/`float64` arrays in memory and on native filesystems, including element access, rectangular slices, missing-chunk fill values and edge chunks. It supports raw chunks and gzip/zstd in both formats, plus zlib in v2, and a documented Blosc subset. Groups and attributes can be read and written for both formats. Native filesystem arrays can also **read** v3 sharding-indexed stores through the same typed API; sharded writes are not supported. A native-only HTTP adapter can download ordinary metadata and encoded chunks touched by a bounded rectangle into a `MemoryStore`; it does not hydrate shards. Rectangular slices batch file I/O and codec work by touched chunk, but still buffer the requested result and are not a streaming typed-array interface. Use it for the documented subset only; other dtypes/codecs and cloud object-store adapters are not implemented yet.

Float32/float64 fill values also support the standard JSON strings `"NaN"`, `"Infinity"`, and `"-Infinity"`. Creating an array with any NaN writes the canonical `"NaN"` fill value; v3 payload-specific hexadecimal NaN fills are not supported.

| Capability | Zarr v2 | Zarr v3 |
| --- | --- | --- |
| Parse regular-grid array metadata | Yes, common string dtypes | Yes, common string data types |
| Metadata and chunk keys | `.` and `/` separators | default and v2-compatible encodings |
| Raw encoded chunk storage | Memory and native filesystem | Memory and native filesystem |
| `bool` element and slice I/O | Memory and native filesystem | Memory and native filesystem; bytes codec |
| `uint8` element and slice I/O | Memory and native filesystem; C/F order | Memory and native filesystem; bytes codec |
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
| zstd compression (levels 0–22) | Read/write | Read/write after bytes codec, with or without frame checksum |
| zlib compression (levels 0–9) | Read/write | Not a v3 core codec |
| Blosc1 frames (LZ4/LZ4HC/Zlib/Zstd; no, byte or bit shuffle) | LZ4 read/write; LZ4HC/Zlib/Zstd read-only; BloscLZ unsupported | LZ4 read/write after bytes codec; LZ4HC/Zlib/Zstd read-only; BloscLZ unsupported |
| Other dtypes, filters and codecs | Planned | Planned |
| Groups, ancestors and attributes | Memory and native filesystem (`.zgroup`/`.zattrs`) | Memory and native filesystem (`zarr.json`) |
| Consolidated metadata | Read-only native `.zmetadata` snapshot | Read-only native inline root `zarr.json` snapshot (zarr-python convention) |
| HTTP read-only regional hydration | Native, bounded metadata/chunk downloads | Native, bounded metadata/chunk downloads |
| Sharding-indexed codec | Not a v2 codec | Native filesystem reads only: start/end index, little/big-endian index, optional CRC32C, supported inner bytes/compression codecs; no writes or HTTP/memory hydration |
| Cloud object-store adapters | Planned | Planned |

## Install and try

Requires a MoonBit toolchain with **`moonc >= 0.10.14`**. Check the compiler version with `moon version --all`; native filesystem/HTTP examples also require native-backend support.

Add the published module to a MoonBit project:

```sh
moon add zlhahaha/zarr@0.2.0
```

For native filesystem/HTTP examples that import `moonbitlang/async` or its subpackages, also add it as a **direct module dependency**:

```sh
moon add moonbitlang/async@0.20.3
```

Installing `zarr` alone does not allow your package to import its transitive `async` dependency. In-memory consumers that do not import `async` need only `zarr`. See the [standalone native quickstart](docs/USAGE.md#native-array-example) for complete package configuration, source and expected output.

To run the repository's examples, clone the [public repository](https://github.com/zlhahaha/zarr):

```sh
git clone https://github.com/zlhahaha/zarr.git
cd zarr
moon update
moon run --target wasm-gc cmd/main
moon run --target native cmd/native_demo
moon run --target native cmd/v2_demo
```

The native examples create temporary v3 and v2 stores, reopen them, verify slice values, and clean up after a successful run. The repository already declares the direct `async` dependency, so `moon update` is sufficient after cloning. See [docs/USAGE.md](docs/USAGE.md) for typed API examples and limits.

## Build and run

Requires `moonc >= 0.10.14` (inspect `moon version --all`), with native support for filesystem and HTTP packages. CI checks native builds and tests on Linux, macOS and Windows, plus wasm-gc on Linux; release packaging and Python interoperability run on Linux. From this directory:

```sh
moon check --target native --deny-warn
moon build --target native
moon test --target native --deny-warn
moon check --target wasm-gc --deny-warn
moon build --target wasm-gc
moon test --target wasm-gc --deny-warn
moon run --target wasm-gc cmd/main
moon run --target native cmd/native_demo
moon run --target native cmd/v2_demo
```

The example creates a v3 `uint8` array and writes a slice across chunks. It prints `Zarr v3 uint8 values: 0,7,9,11`.
The first native example creates and reopens a v3 zstd-compressed `uint16` array in a temporary filesystem store. The v2 example does the same with a gzip-compressed, big-endian `int16` array and verifies a rectangular read after reopening. All examples exit with an error if their checks fail. See [docs/USAGE.md](docs/USAGE.md) for the public API and format limits.

Typed operations return `None`/`false` for validation or decoding failures, but native filesystem operations can propagate I/O exceptions. Missing chunks read as fill values, not errors. See [error handling](docs/USAGE.md#error-handling) for the distinction and a `catch` example; multi-chunk writes are not atomic.

## Interoperability tests

Native tests read forty-three committed v2/v3 sample stores generated by zarr-python 3.4.0, covering numeric and boolean types, signed bytes, full-range 64-bit integers, non-finite floating fills, gzip/zlib/zstd including checked frames, Blosc LZ4/Zstd with byte and bit shuffle, nested groups, both consolidated-metadata conventions, and four v3 sharding-indexed layouts. The generators include [scripts/generate_sharding_fixtures.py](scripts/generate_sharding_fixtures.py), [scripts/generate_blosc_fixtures.py](scripts/generate_blosc_fixtures.py), [scripts/generate_blosc_bitshuffle_fixtures.py](scripts/generate_blosc_bitshuffle_fixtures.py), [scripts/generate_zstd_checksum_fixture.py](scripts/generate_zstd_checksum_fixture.py), and [scripts/generate_v3_consolidated_fixture.py](scripts/generate_v3_consolidated_fixture.py) alongside the other scripts listed in [the fixture inventory](integration/fixtures/zarr-python/README.md). In the reverse direction, the `cmd/interop`, `cmd/nonfinite_interop`, `cmd/int64_interop`, `cmd/int8_interop`, and `cmd/blosc_interop` generators write thirty-two stores—including v2/v3 Blosc LZ4 frames, a multi-chunk compressed slice, boolean masks, non-finite fills, full-range 64-bit integers, signed bytes and v2/v3 nested groups—to the ignored `integration/.roundtrip/` directory. [The main verifier](scripts/verify_moonbit_roundtrip.py) and [Blosc verifier](scripts/verify_blosc_roundtrip.py) open them with zarr-python. CI installs the pinned Python test oracle and runs both directions. The generators refuse to overwrite existing stores; remove only their generated directories before re-running locally.

## Design

Both formats share a storage-neutral array API, but retain their distinct metadata, chunk-key, dtype, and codec rules. Unknown or unsupported encodings must fail explicitly instead of returning incorrect values. The MoonBit packages follow one-way dependencies:

```text
metadata/        Parse and validate v2/v3 array and group documents
chunk/           Regular-grid indexing and metadata/chunk keys
shard/           V3 sharding layout and bounded index validation
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

This project implements the publicly documented [Zarr v2 storage specification](https://zarr-specs.readthedocs.io/en/latest/v2/v2.0.html), [Zarr v3 core specification](https://zarr-specs.readthedocs.io/en/latest/v3/core/), and [sharding-indexed codec specification](https://zarr-specs.readthedocs.io/en/latest/v3/codecs/sharding-indexed/index.html). The [Zarr specifications repository](https://github.com/zarr-developers/zarr-specs) is CC BY 4.0. The Blosc codec follows the public [C-Blosc chunk-format description](https://github.com/Blosc/c-blosc/blob/main/README_CHUNK_FORMAT.rst) and [LZ4 block format](https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md) (the reference projects have BSD-style licenses); no upstream implementation code was copied. The committed interoperability stores were generated by this repository's original scripts using [zarr-python 3.4.0](https://github.com/zarr-developers/zarr-python), which is MIT-licensed; see [integration/fixtures/zarr-python/README.md](integration/fixtures/zarr-python/README.md). Compression uses the Apache-2.0 MoonBit dependencies [moonbit-community/flate](https://mooncakes.io/docs/moonbit-community/flate) and [Milky2018/zstd](https://mooncakes.io/docs/Milky2018/zstd).

This project is licensed under Apache-2.0; see [LICENSE](LICENSE).
