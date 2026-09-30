# Zarr implementation roadmap

The name “Zarr” means the library targets both Zarr storage format 2 and 3. It does **not** imply that all format extensions/codecs or the entire zarr-python API are implemented. Every phase has a testable exit gate; README support claims must follow passing gates.

## Stage 0 — Project foundation (local and remote gates passed)

- MoonBit package, Apache-2.0 license, source attribution, Git history, CI, a separate off-repository contest proposal, and runnable example.
- Parse regular-grid metadata for v2/v3; generate safe logical paths and chunk keys; reject malformed/ambiguous metadata.
- In-memory byte store for metadata and already-encoded chunks.
- Gate: `moon check --deny-warn`, `moon build`, `moon test --deny-warn`, and `moon run cmd/main` pass locally and in GitHub Actions.

Native/wasm-gc checks, builds, tests and example runs pass locally and in [GitHub Actions](https://github.com/zlhahaha/zarr/actions/workflows/ci.yml). The release archive is validated in CI; Mooncakes `0.1.0` was published on 2026-09-25.

## Stage 1 — Useful uncompressed numeric arrays

Current implementation: typed `bool`, signed/unsigned 8/16/32/64-bit integers, and `float32`/`float64` create/open/element and rectangular-slice I/O in memory and native filesystem, plus v2/v3 group/attribute operations and safe ancestor creation. The `int8` API uses range-checked `Int` values because MoonBit has no dedicated `Int8` type. Slices batch file I/O and codec work by touched chunk but still buffer the requested result. Fifty-one independent zarr-python 3.4.0 fixtures are read by native tests, and zarr-python reads forty MoonBit-generated stores in CI, including Blosc LZ4 writes, a multi-chunk compressed slice, non-finite floating fills, boolean masks, signed bytes, full-range 64-bit integers and nested groups. Explicit 3D image-volume and 4D feature-tensor checks include v2 C/F order, endian variants, missing/edge chunks, overwrite/reopen and compressed/sharded reads. See [INTEROPERABILITY.md](INTEROPERABILITY.md). Extended dtypes remain open.

- Store abstraction and native filesystem backend; create/open arrays and groups, metadata/attributes, and chunks for v2/v3.
- Core numeric dtypes (`bool`, signed/unsigned 8/16/32/64-bit, float32/64) with specified endian handling; C-order v2 and v3 bytes codec.
- Read/write a full chunk and a bounded N-dimensional rectangular slice, including edge chunks and absent-chunk fill values.
- Gate: separately generated zarr-python v2 and v3 datasets round-trip with MoonBit; invalid metadata, paths, ranks, ranges and byte lengths fail explicitly.

## Stage 2 — Common real-world codecs and v2 compatibility (partial)

Implemented locally: gzip and zstd read/write for v2/v3, including optional v3 Zstd frame checksums, zlib read/write for v2, Blosc1 LZ4 read/write with no, byte or bit shuffle (other Blosc compressors read-only), bounded or preflight-checked decompression, rejection of unsupported v2 filters, v2 consolidated metadata read-only snapshots, and sixteen independent compressed Python read fixtures. Zstd frames without content size may be conservatively rejected.

- v3 codec pipeline: bytes plus zstd and gzip; v2 compressor/filter adapter for raw, gzip/zlib, zstd and Blosc. Non-LZ4 Blosc writes, BloscLZ/Snappy and v2 filters remain open.
- v2 `.` and `/` chunk separators, F-order, `.zattrs`, `.zgroup`, and consolidated `.zmetadata` reads (implemented as read-only snapshots).
- Gate: compare against zarr-python fixtures across dtypes, endianness, fill values, partial chunks and codec combinations; document unsupported codecs.

## Stage 3 — Hierarchies, scale and deployment

Partial implementation through `0.7.0`: `chunk.RegionTileCursor` incrementally plans bounded N-D rectangles, but typed reads still buffer each tile. `store/http` hydrates ordinary v2/v3 chunks and supported v3 shard indexes/selected inner payload ranges from read-only HTTP; `store/s3` reuses that remote reader for anonymous or explicitly signed path-style S3-compatible GETs. The shared remote path validates response ranges and distinguishes 404 missing data from failures, with per-request timeouts, one transient retry and resource caps. `HttpStore::open_array` and `S3Store::open_array` expose validated metadata before data transfer. Live public OME-Zarr `uint8`/Zstd data and a 256 MiB logical tiled scan are reproducible; neither is a broad production-cloud benchmark or measured aggregate-RAM guarantee. Native `FileStore::open_consolidated_v3` reads the zarr-python inline root-index convention as a read-only snapshot. Native filesystem sharded reads still use bounded index/inner-chunk file ranges; six Python fixtures cover layouts, missing chunks, edges and explicit 3D/4D data. Sharded writes, remote writes and writable consolidated metadata remain open.

- Group traversal and metadata mutation remain open. Filesystem, HTTP and S3 read paths exist; HTTP has an encoded full-object LRU cache, while tile traversal bounds each caller-requested result rather than exposing a streaming typed-array handle.
- V3 sharding-indexed reads work on native filesystem and through strict HTTP/S3 Range hydration; sharded writes, other object-store services, remote write support and writable consolidated metadata remain open. The HTTP/S3 range transport is shared, but a universal filesystem/network Store trait is not yet public or assumed stable.
- Native multi-chunk/shard latency and OS peak-memory benchmark harness implemented with independent synthetic stores, fresh-process trials, cache-on/off comparisons and Linux/macOS/Windows native CI smoke reproduction. Typed region reads reuse validated indexes in bounded operation-local FIFO caches. See [BENCHMARKS.md](BENCHMARKS.md); this only measures the documented workloads, not general large-scale dataset performance or streaming whole-array memory bounds.
- Read resource budgets implemented: shared immutable policies for metadata/chunk sizes, region bytes/elements/count, rank and JSON depth; same-handle native size checks, explicit over-budget exceptions, and cumulative HTTP hydration bytes. See [RESOURCE_LIMITS.md](RESOURCE_LIMITS.md). These are per-input/work protections, not streaming or aggregate RAM guarantees.
- Single-key filesystem write safety implemented for `0.5.0`: exclusive same-directory staging, complete data-synchronized writes, handle closure, replacement rename and cancellation-safe owned-temp cleanup. Fault-injection/public regressions cover partial write/rename failures, collisions, cleanup failure, cooperative cancellation, open readers and concurrent complete-key writers. See [WRITE_SAFETY.md](WRITE_SAFETY.md). Multi-key transactions, concurrent read-modify-write locking, directory-sync crash durability and broader filesystem guarantees remain open.
- Gate: read representative scientific datasets without loading the whole array; cross-language tests and performance/memory benchmarks.

## Stage 4 — Release and maintenance

CI covers native check/build/test, examples and benchmark smoke reproduction on Linux, macOS and Windows, plus wasm-gc check/build/test and the in-memory example on Linux. Release packaging and the older Python reverse tests run on Linux; new 3D/4D reverse tests run on all three native platforms. A deterministic property test checks 120 N-dimensional chunk/region partitions on native and wasm-gc. Mooncakes versions `0.1.0` through `0.6.0` are published. The `0.4.0` milestone adds read budgets and malformed-input regression checks; `0.5.0` adds safe single-key filesystem replacement. Both passed independent published-package consumer verification; `0.5.0` passed 116 native and 58 wasm-gc source tests and its consumer passed six public-API checks plus the compressed replacement example. Exhaustive fuzzing and broader real-world performance validation remain open. Published `0.6.0` passes 124 native and 64 wasm-gc tests and replaces per-element read coordinates with validated strided row spans. Its paired 0.5.0 comparison and OS peak-memory evidence are recorded in [BENCHMARKS.md](BENCHMARKS.md); real-data and 3D/4D throughput remain unmeasured. All four release CI jobs passed, including the N-D reverse checks on each native OS. An independent registry consumer passed strict native check/build, 8 native / 6 wasm-gc public-API tests, the quickstart and N-D example, and Python verification of eight generated stores.

The `0.7.0` candidate adds typed tile traversal, HTTP/S3 sharded hydration, explicit SigV4 credentials, real public-data checksum verification and native CI execution of the 256 MiB logical tiled scan. The earlier versions `0.1.0`–`0.6.0` remain published; update this release status only after Mooncakes publication and independent consumer checks. Native private AWS/MinIO interoperability, total-memory/real-world throughput measurements and remote writes are not established by the local mock or public anonymous example.

- Public Mooncakes release with versioned API docs, installation snippet, examples, changelog and support matrix.
- Linux/macOS/Windows and supported MoonBit backends in CI; fuzz/property tests for metadata and chunk boundaries.
- Gate: external user can follow README to open, slice, modify and save at least one v2 and one v3 dataset; all claims are backed by tests.

Non-goals for the first release: implementing a general-purpose ndarray math library, every third-party codec, and full zarr-python API parity. Interop with existing MoonBit numeric array libraries is preferred over duplicating them.
