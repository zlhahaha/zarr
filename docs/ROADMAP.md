# Zarr implementation roadmap

The name “Zarr” means the library targets both Zarr storage format 2 and 3. It does **not** imply that all format extensions/codecs or the entire zarr-python API are implemented. Every phase has a testable exit gate; README support claims must follow passing gates.

## Stage 0 — Project foundation (local gate passed; remote gate pending)

- MoonBit package, Apache-2.0 license, source attribution, Git history, CI, proposal and runnable example.
- Parse regular-grid metadata for v2/v3; generate safe logical paths and chunk keys; reject malformed/ambiguous metadata.
- In-memory byte store for metadata and already-encoded chunks.
- Gate: `moon check --deny-warn`, `moon build`, `moon test --deny-warn`, and `moon run cmd/main` pass locally and in GitHub Actions.

Local native/wasm-gc checks, builds, tests and example runs pass. GitHub Actions has not run because the repository is intentionally not pushed yet.

## Stage 1 — Useful uncompressed numeric arrays

Current implementation: typed `uint8`, `uint16`, `int32`, `float32`, and `float64` create/open/element and rectangular-slice I/O in memory and native filesystem, plus v2/v3 group/attribute operations. Slices batch file I/O and codec work by touched chunk but still buffer the requested result. Twelve independent zarr-python 3.4.0 fixtures are read by native tests, and zarr-python reads thirteen MoonBit-generated stores locally, including a multi-chunk compressed slice. The remaining dtype breadth is open; GitHub CI has not yet run.

- Store abstraction and native filesystem backend; create/open arrays and groups, metadata/attributes, and chunks for v2/v3.
- Core numeric dtypes (`bool`, signed/unsigned 8/16/32/64-bit, float32/64) with specified endian handling; C-order v2 and v3 bytes codec.
- Read/write a full chunk and a bounded N-dimensional rectangular slice, including edge chunks and absent-chunk fill values.
- Gate: separately generated zarr-python v2 and v3 datasets round-trip with MoonBit; invalid metadata, paths, ranks, ranges and byte lengths fail explicitly.

## Stage 2 — Common real-world codecs and v2 compatibility (partial)

Implemented locally: gzip and zstd read/write for v2/v3, zlib read/write for v2, bounded or preflight-checked decompression, rejection of unsupported v2 filters, and five independent compressed Python fixtures in each interoperability direction. v3 zstd checksum=true is not emitted or accepted yet; zstd frames without content size may be conservatively rejected.

- v3 codec pipeline: bytes plus zstd and gzip; v2 compressor/filter adapter for raw, gzip/zlib, zstd and Blosc where dependencies permit. Blosc and filters remain open.
- v2 `.` and `/` chunk separators, F-order, `.zattrs`, `.zgroup`, and consolidated `.zmetadata` reads.
- Gate: compare against zarr-python fixtures across dtypes, endianness, fill values, partial chunks and codec combinations; document unsupported codecs.

## Stage 3 — Hierarchies, scale and deployment

- Group traversal and metadata mutation, filesystem and HTTP read-only stores; configurable chunk cache and bounded streaming.
- v3 sharding-indexed codec and consolidated metadata; optional cloud/object-store adapter after the base Store API is stable.
- Gate: read representative scientific datasets without loading the whole array; cross-language tests and performance/memory benchmarks.

## Stage 4 — Release and maintenance

- Public Mooncakes release with versioned API docs, installation snippet, examples, changelog and support matrix.
- Linux/macOS/Windows and supported MoonBit backends in CI; fuzz/property tests for metadata and chunk boundaries.
- Gate: external user can follow README to open, slice, modify and save at least one v2 and one v3 dataset; all claims are backed by tests.

Non-goals for the first release: implementing a general-purpose ndarray math library, every third-party codec, and full zarr-python API parity. Interop with existing MoonBit numeric array libraries is preferred over duplicating them.
