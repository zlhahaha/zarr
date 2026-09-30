# Zarr

[![CI](https://github.com/zlhahaha/zarr/actions/workflows/ci.yml/badge.svg)](https://github.com/zlhahaha/zarr/actions/workflows/ci.yml)

A MoonBit implementation of the Zarr v2 and v3 storage formats for chunked N-dimensional arrays. This is an independent implementation, not an official Zarr Developers project.

## Status

Early Mooncakes release (version `0.7.0`). The library reads and writes `bool`, signed/unsigned 8/16/32/64-bit integers, and `float32`/`float64` arrays in memory and on native filesystems, including elements, rectangular slices, missing-chunk fills and edge chunks. It supports raw chunks and gzip/zstd in both formats, plus zlib in v2 and a documented Blosc subset. Groups and attributes work in both formats. Native filesystem arrays can **read** v3 sharding-indexed stores; sharded writes remain unsupported. Native read-only HTTP and S3 adapters now hydrate selected ordinary chunks **or selected inner chunks of shards** into a temporary `MemoryStore`. A tile cursor lets applications process a large logical rectangle one bounded typed `read_region` at a time. Each tile is still buffered, so this is not a zero-copy or automatically streaming typed-array API. Unsupported dtypes/codecs, cloud writes and concurrent-writer snapshots remain outside the supported subset.

Float32/float64 fill values also support the standard JSON strings `"NaN"`, `"Infinity"`, and `"-Infinity"`. Creating an array with any NaN writes the canonical `"NaN"` fill value; v3 payload-specific hexadecimal NaN fills are not supported.

| Capability | Zarr v2 | Zarr v3 |
| --- | --- | --- |
| Parse regular-grid array metadata | Yes, common string dtypes | Yes, common string data types |
| Metadata and chunk keys | `.` and `/` separators | default and v2-compatible encodings |
| Raw encoded chunk storage | Memory and native filesystem | Memory and native filesystem |
| Safe single-key filesystem replacement | Native: exclusive sibling staging + replace | Native: exclusive sibling staging + replace |
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
| Incremental N-D tile traversal | `chunk.RegionTileCursor`, caller reads each bounded tile | Same; no whole-result allocation by the cursor |
| gzip compression (levels 0–9) | Read/write | Read/write after bytes codec |
| zstd compression (levels 0–22) | Read/write | Read/write after bytes codec, with or without frame checksum |
| zlib compression (levels 0–9) | Read/write | Not a v3 core codec |
| Blosc1 frames (LZ4/LZ4HC/Zlib/Zstd; no, byte or bit shuffle) | LZ4 read/write; LZ4HC/Zlib/Zstd read-only; BloscLZ unsupported | LZ4 read/write after bytes codec; LZ4HC/Zlib/Zstd read-only; BloscLZ unsupported |
| Other dtypes, filters and codecs | Planned | Planned |
| Groups, ancestors and attributes | Memory and native filesystem (`.zgroup`/`.zattrs`) | Memory and native filesystem (`zarr.json`) |
| Consolidated metadata | Read-only native `.zmetadata` snapshot | Read-only native inline root `zarr.json` snapshot (zarr-python convention) |
| HTTP read-only regional hydration | Native, bounded metadata/chunk downloads | Native, bounded ordinary or shard-index/payload byte-range downloads |
| Sharding-indexed codec | Not a v2 codec | Native filesystem and HTTP/S3 read-only: start/end index, little/big-endian index, optional CRC32C, supported inner codecs; no writes |
| S3-compatible object storage | Native, read-only regional hydration | Native, read-only ordinary/sharded regional hydration; anonymous or explicit SigV4 credentials |

## Install and try

Requires a MoonBit toolchain with **`moonc >= 0.10.14`**. Check the compiler version with `moon version --all`; native filesystem/HTTP examples also require native-backend support.

Add the published module to a MoonBit project:

```sh
moon add zlhahaha/zarr@0.7.0
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
moon run --target native cmd/budget_demo
moon run --target native cmd/nd_demo
moon run --target native cmd/tile_demo
moon run --target native cmd/real_bonsai  # optional: accesses a public AWS dataset
moon run --target native cmd/real_bonsai --volume  # optional: eight real compressed chunks
```

The local native examples create temporary stores or use memory only. `cmd/tile_demo` scans a 256 MiB *logical*, sparsely filled array through 256 tiles of at most 1 MiB each; it verifies a whole-region request is rejected under default limits. `cmd/real_bonsai` reads a public OME-Zarr microscopy dataset from AWS; its `--volume` mode validates an eight-object 128³ ROI with an independently checked checksum and a single-host sampled 10.84 MiB working-set peak. It requires network access and is deliberately not a required CI gate. The repository already declares the direct `async` dependency, so `moon update` is sufficient after cloning. See [remote and tiled reads](docs/REMOTE.md) for the measured scope and caveats, and [docs/USAGE.md](docs/USAGE.md).

## Build and run

Requires `moonc >= 0.10.14` (inspect `moon version --all`), with native support for filesystem and HTTP packages. CI checks native builds and tests on Linux, macOS and Windows, plus wasm-gc on Linux; release packaging and the older Python reverse tests run on Linux; new 3D/4D reverse tests run on all three native platforms. From this directory:

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
moon run --target native cmd/tile_demo
```

The example creates a v3 `uint8` array and writes a slice across chunks. It prints `Zarr v3 uint8 values: 0,7,9,11`.
The first native example creates and reopens a v3 zstd-compressed `uint16` array in a temporary filesystem store. The v2 example does the same with a gzip-compressed, big-endian `int16` array and verifies a rectangular read after reopening. All examples exit with an error if their checks fail. See [docs/USAGE.md](docs/USAGE.md) for the public API and format limits.

Typed operations return `None`/`false` for validation or decoding failures, but native filesystem operations can propagate I/O exceptions. Missing chunks read as fill values, not errors. See [error handling](docs/USAGE.md#error-handling) for the distinction and a `catch` example; multi-chunk writes are not atomic.

## Interoperability tests

Native tests read **51 committed stores** generated by zarr-python 3.4.0; Python verifies **40 MoonBit-written stores** in reverse. New coverage explicitly checks 3D `uint16` image volumes and 4D `float32` time/space/feature tensors, v2 C/F order, little/big endian, raw/gzip/zlib/zstd, missing and non-divisible edge chunks, non-aligned regions and persistence after an existing-chunk overwrite. Two new N-D fixtures also test start/end-index v3 shards, bringing shard layouts to six. The N-D reverse checks run on Linux/macOS/Windows native; portable N-D memory tests also run on wasm-gc. See [coverage and reproducible commands](docs/INTEROPERABILITY.md) and [fixture inventory](integration/fixtures/zarr-python/README.md). Existing checks include booleans, signed bytes, full-range integers, non-finite fills, Blosc, nested groups and consolidated metadata. This is format interoperability, not an ML framework or a guarantee for every scientific-data convention.

## Read performance and memory

`chunk.RegionTileCursor` plans validated C-order N-D tiles without enumerating the full selection or multiplying its total element count. A caller reads and processes each tile with the existing typed array API. The cursor's `max_tile_elements` controls one tile; each typed read is separately subject to `ReadLimits`. The runnable 256 MiB sparse-array scan and live 3D bioimage sample are described in [REMOTE.md](docs/REMOTE.md). This is bounded **per operation**, not a measured total-process memory guarantee, and it does not alter historical 0.5.0→0.6.0 benchmark claims.

Native typed region reads now reuse validated shard indexes within each call, with a configurable FIFO cap of 16 MiB / 64 entries by default. No index persists across calls. Set `FileStore::new(path, shard_index_cache_bytes=0)` to compare without caching; per-store `shard_read_stats()` reports explicit index/payload range reads and cache hits. This is not a concurrent-writer snapshot or a persistent chunk cache.

The [benchmark guide](docs/BENCHMARKS.md) provides independent zarr-python datasets, cache-on/off comparisons, every-value checks, monotonic slice timings and **OS reader-process peak resident memory**, with fresh processes per trial. The full profile covers 32 MiB logical arrays and slices touching up to 1089 chunks; Linux/macOS/Windows native CI reproduces a smaller smoke run and uploads the measurements without machine-dependent performance thresholds. These are synthetic local-filesystem measurements, not a cold-disk test or proof of fully validated large-scale/whole-array performance. Results remain buffered, and the index-cache byte cap is not a total-memory cap.

Version `0.6.0` also replaces per-element read coordinates and discarded chunk keys with validated strided row spans, including native typed result assembly. In a Windows five-trial **alternating-version comparison against 0.5.0**, the synthetic 2048² raw case measured 5256.33→133.76 ms (39.3×), gzip 5633.11→524.74 ms (10.7×), and gzip shards 5400.29→477.26 ms (11.3×). Max reader peak remained about 14.7–15.1 MiB; no peak-memory reduction is claimed. Exact values and range-read counts were checked for both versions. These ratios apply only to those measured 2D `uint16` selections; 3D/4D correctness tests are not 3D/4D throughput measurements. See [paired raw reports, intermediate stages, ranges and reproduction](docs/BENCHMARKS.md#050--060-region-read-comparison-2026-09-29).

## Read resource budgets

Since `0.4.0`, native and in-memory typed arrays share configurable `store.ReadLimits`: 1 MiB metadata, 64 MiB encoded/decoded chunks, 64 MiB logical region data, 8388608 region elements, 16384 touched chunks, rank 64 and JSON nesting 64 by default. Region counts are checked without enumeration before result allocation; native files are size-checked on their opened handle before a fixed-length read. Oversized file inputs raise `fs.ReadLimitExceeded`, never missing-chunk fill values. Typed region/decode rejection returns `None`; missing data retains its fill behavior. HTTP/S3 uses the shared policy plus a 64 MiB cumulative encoded hydration cap; selected shard index bytes count toward that cap.

Pass `read_limits=limits` to `MemoryStore::new`, `FileStore::new`, consolidated openers, `HttpStore::new` or `S3Store::new`. Every policy cap must be positive; explicit increases are available for trusted workloads. These are input/work budgets, **not total-memory, streaming or concurrent-writer guarantees**. Raw in-memory map access and direct low-level codec/parser calls are caller-managed. See [configuration, failure semantics and regression tests](docs/RESOURCE_LIMITS.md). Run `moon run --target native cmd/budget_demo` for an executable rejection/recovery example.

## Filesystem write safety

Since `0.5.0`, `FileStore::put` writes to an exclusively created `.zarr-tmp-*` file in the destination's directory. It completes the data-synchronized write and closes the handle before replacing the destination by rename; it never deletes or truncates the old destination as a fallback. This path also applies to ordinary chunks, metadata and attributes written through the native typed APIs. A pre-replacement write/rename failure leaves the previous target intact (or absent if new) and cleans up only the owned temporary file. Cooperative cancellation runs protected cleanup; a replacement already in progress can complete despite cancellation.

This is **single-key replacement, not a multi-chunk transaction, concurrent read-modify-write lock, whole-store snapshot or power-loss durability guarantee**. Safe visibility depends on the filesystem's same-directory rename semantics. Cleanup failure raises `fs.WriteCleanupFailed` with the temporary path and diagnostic; forced termination may leave staging files. Replacement creates a new file rather than preserving inode identity, hard links or custom permissions. See [failure contracts, recovery and reproducible tests](docs/WRITE_SAFETY.md).

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
store/s3/        Native-only read-only S3-compatible adapter with SigV4
array/           Typed array creation, element and region I/O
hierarchy/       Group and attribute operations
integration/     Cross-package tests
cmd/main/        Portable in-memory v3 example
cmd/native_demo/ Native filesystem v3 example
cmd/v2_demo/     Native filesystem v2 example
cmd/budget_demo/ Native read-budget rejection and recovery example
cmd/nd_demo/     Native 3D image / 4D feature-tensor example
cmd/nd_interop/  N-D reverse interoperability generator
cmd/tile_demo/   Full logical 256 MiB scan using bounded tile reads
cmd/real_bonsai/ Optional live public OME-Zarr AWS read example
cmd/benchmark/   Native read latency and OS peak-memory instrumentation
scripts/         Independent data generation, interoperability and benchmarks
```

The public array functions live in `zlhahaha/zarr/array`; `MemoryStore` lives in `zlhahaha/zarr/store`, and format constants in `zlhahaha/zarr/metadata`. For example, `@array.create_u8(store, @metadata.V3, "samples", [4], [2], b'\x00', compression=@codec.Zstd(3))` creates a compressed v3 array without hand-writing metadata JSON. On native, `FileStore::create_u8` accepts the same `compression` option. gzip/zlib output is bounded while decoding; zstd frames are preflight-checked against the declared chunk size using the dependency's frame-size bound. Thus, valid zstd frames without a known content size may be rejected if the conservative bound exceeds the chunk size. See [the roadmap](docs/ROADMAP.md) for the staged interoperability targets.

## Specification and attribution

This project implements the publicly documented [Zarr v2 storage specification](https://zarr-specs.readthedocs.io/en/latest/v2/v2.0.html), [Zarr v3 core specification](https://zarr-specs.readthedocs.io/en/latest/v3/core/), and [sharding-indexed codec specification](https://zarr-specs.readthedocs.io/en/latest/v3/codecs/sharding-indexed/index.html). The [Zarr specifications repository](https://github.com/zarr-developers/zarr-specs) is CC BY 4.0. The Blosc codec follows the public [C-Blosc chunk-format description](https://github.com/Blosc/c-blosc/blob/main/README_CHUNK_FORMAT.rst) and [LZ4 block format](https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md) (the reference projects have BSD-style licenses); no upstream implementation code was copied. The committed interoperability stores were generated by this repository's original scripts using [zarr-python 3.4.0](https://github.com/zarr-developers/zarr-python), which is MIT-licensed; see [integration/fixtures/zarr-python/README.md](integration/fixtures/zarr-python/README.md). Compression uses the Apache-2.0 MoonBit dependencies [moonbit-community/flate](https://mooncakes.io/docs/moonbit-community/flate) and [Milky2018/zstd](https://mooncakes.io/docs/Milky2018/zstd); S3 SigV4 uses [moonbitlang/x](https://mooncakes.io/docs/moonbitlang/x) SHA-256/HMAC and UTC conversion. The optional real-data example reads the publicly documented [OME-Zarr OpenSciVis dataset](https://github.com/InsightSoftwareConsortium/OMEZarrOpenSciVisDatasets) without distributing its bytes in this repository.

This project is licensed under Apache-2.0; see [LICENSE](LICENSE).
