# Changelog

## 0.5.0 — Safe single-key filesystem replacement

- Replace direct destination truncation with exclusive sibling `.zarr-tmp-*` staging, complete data-synchronized writes, handle closure and replacement rename. Ordinary native chunks, metadata and attributes share this path; no delete-then-rename fallback is used.
- Retry temporary-name collisions up to 128 attempts without opening/truncating or deleting foreign files. Handle concurrent parent-directory creation without swallowing an existing non-directory error.
- Register owned-temp cleanup with `errdefer` and protect acquisition, commit and cleanup from cancellation at ownership boundaries. A commit already in progress can complete despite cancellation; completed keys are not rolled back.
- Add `fs.WriteCleanupFailed(temporary_path, diagnostic)` when cleanup fails; this error supersedes the original operation failure and exposes the orphan path. Forced termination can leave temporary files; no automatic orphan sweeper is provided.
- Add 14 write-safety regressions: partial writes/commit failures on existing and absent keys, collisions/exhaustion, creation/cleanup failures, cooperative cancellation (including acquired empty writes), protected commit, actual rename rejection, replacement lengths/empty values, retained reader handles, concurrent writers and partial multi-chunk failure. Update the native v3 example to overwrite existing compressed chunks.
- Document the filesystem-dependent single-key visibility contract, new-file identity/permissions and symlink/hard-link behavior, recovery, staging space requirements and explicit exclusions: no multi-key transaction, write lock, snapshot or power-loss durability guarantee. Existing measured read performance remains the `0.3.0` baseline.

## 0.4.0 — Read resource budgets and malformed-data regression checks

- Add immutable configurable `store.ReadLimits` policies for metadata, encoded/decoded chunks, logical region bytes/elements, touched chunks, rank and JSON nesting. Defaults intentionally reject formerly accepted oversized inputs; all policy caps must be positive.
- Check touched chunk counts without allocating coordinate lists; preflight typed regions before enumeration/result buffers and declared chunk sizes before fill/codec allocations. Native temporary memory views inherit their filesystem policy, including explicit increases.
- Replace native unbounded read-to-EOF with same-handle size checks and fixed-length reads. Raise `fs.ReadLimitExceeded` for oversized inputs instead of treating them as absent chunks. Consolidated openers accept the policy.
- Preflight JSON nesting in constant space before parsing, respecting quoted/escaped strings. Check encoded/expected decoded sizes before codec invocation. Preserve missing-fill semantics and explicit native I/O exceptions.
- Apply shared policies to HTTP hydration and add a cumulative encoded-byte cap; keep existing stricter HTTP settings. Raw memory-map access and direct low-level codecs/parsers remain caller-managed.
- Add executable native budget/recovery example and regression checks for huge selections, policy boundaries, rank/depth, scalar/empty regions, gzip expansion, truncated gzip/zstd/checked-zstd/Blosc frames, consolidated indexes, shard payloads and HTTP budgets. Input/work budgets do not guarantee total RAM, deadlines, transactional writes or streaming behavior.

## 0.3.0 — Measured native reads and operation-local shard indexes

- Add reproducible synthetic benchmarks for v2 gzip, v3 raw/gzip, gzip shards, and an index-heavy raw shard layout. Measure multi-chunk slice wall time and native reader-process OS peak resident memory in fresh processes; verify every returned value. Keep raw samples, cache comparisons and measurement limits documented.
- Reuse length/CRC32C-validated indexes within a native typed region read using a bounded FIFO cache, defaulting to 16 MiB of index payload and 64 entries. Support configurable caps and disabling. Check entry offsets/lengths on every use; retain no indexes across operations or handles/payloads in the cache.
- Expose per-store shard range-read/cache counters. Add regression tests for cache caps/eviction, cache-off equivalence, index variants, same-store file changes, corrupted checksums and truncated shards.
- Add Linux/macOS/Windows native CI benchmark smoke runs and artifacts, without machine-dependent speed/RSS thresholds. Document that buffered regions and synthetic benchmarks do not establish large-scale/streaming performance guarantees.
- Clarify native direct async dependencies, minimum `moonc >= 0.10.14`, complete standalone quickstart and filesystem exception handling.

## 0.2.0 — Zarr v3 sharding-indexed reads

- Read Zarr v3 sharding-indexed arrays through the native filesystem typed-array API, including element and rectangular-region reads, missing inner-chunk fill values, and edge shards. Sharded arrays are read-only; writes and the in-memory/HTTP adapters do not yet support shard updates or hydration.
- Read a bounded shard index and only the selected encoded inner chunk, rather than loading the entire shard. Support start/end indexes, little/big-endian index bytes, optional CRC32C verification, and the documented inner bytes/compression codecs. Reject malformed indexes and unsupported codec chains.
- Add four independent zarr-python 3.4.0 sharding fixtures and index-validation tests. The fixture inventory now contains 43 stores.

## 0.1.0 — First Mooncakes release

Initial interoperable subset of Zarr storage formats 2 and 3 for MoonBit.

- Read and write regular-grid arrays of `bool`, signed/unsigned 8/16/32/64-bit integers, and `float32`/`float64` in memory and on native filesystems, including element access, rectangular regions, edge chunks, and missing-chunk fill values. Full-range 64-bit integer fills retain exact JSON representation; `int8` uses range-checked `Int` values.
- Encode and decode canonical `NaN` and positive/negative infinity fills for float32/float64 in both formats.
- Read and write v2 and v3 groups and attributes; read v2 consolidated metadata as a read-only native snapshot.
- Read zarr-python's v3 inline consolidated metadata from a read-only native snapshot.
- Support raw, gzip, and zstd chunks in both formats, plus v2 zlib; v3 Zstd frame checksums can be read and written. Unsupported codecs and filters fail explicitly.
- Read a bounded Blosc1 subset (LZ4/LZ4HC, Zlib, Zstd; no, byte or bit shuffle) from v2/v3 stores, including multi-block and incompressible frames. Write LZ4 Blosc1 chunks with any of the three shuffle modes and a memcpy fallback; other Blosc compressors remain read-only.
- Hydrate a bounded region of a static HTTP-served array into a `MemoryStore` on native targets. The read-only adapter has a configurable bounded in-memory LRU cache; it has no disk cache.
- Verify interoperability in both directions with zarr-python 3.4.0, and run native CI on Linux, macOS, and Windows plus wasm-gc CI on Linux.

See the [support table](README.md#status) and [known limits](docs/USAGE.md#supported-format-subset) before using this early version.
