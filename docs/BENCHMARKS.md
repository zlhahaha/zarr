# Native read latency and peak memory

This benchmark measures ordinary multi-chunk rectangular reads and v3 sharding-indexed reads. It is a reproducible synthetic workload, **not evidence that large-scale scientific workloads or terabyte arrays have been fully performance-validated**. No speed or RSS threshold is enforced in CI.

## Reproduce

Requires `moonc >= 0.10.14`, a native C toolchain, Python 3.12 or newer, and the pinned independent data generator:

```sh
moon update
python -m pip install zarr==3.4.0 numpy==2.5.3
python scripts/benchmark_reads.py --trials 5 --work-dir _build/bench-data --output _build/bench-results.json
```

The script builds only `cmd/benchmark` in native **release** mode, creates new stores, and refuses to overwrite existing datasets or reports. To repeat against the same generated data, use `--reuse` with a new report path. CI uses the smaller smoke profile:

```sh
python scripts/benchmark_reads.py --quick --trials 2 --work-dir _build/bench-smoke --output _build/bench-smoke.json
```

The full profile has four 4096×4096 `uint16` arrays (32 MiB logical data each): v2 gzip, v3 raw, v3 gzip, and v3 gzip shards. Ordinary/inner chunks are 64×64; gzip shards are 512×512. Reads start at `[7, 11]` with extents 256×256, 1024×1024 and 2048×2048, touching 25, 289 and 1089 chunks respectively. A separate 1024×1024 raw sharded array uses 8×8 inner chunks and a single outer shard. Its 256×256 read touches 1089 inner chunks and stresses a 262148-byte CRC32C index. The deterministic value formula is `(row * 17 + column * 31) % 65521 + 1`.

Each trial launches a fresh reader process. One initial trial per case/mode is discarded; five trials are retained in the full run. Cache-on/off order alternates. The reader validates **every** returned value and reports a checksum; the driver checks range-read counts as well as identical cached/uncached results. Input generation and compilation are outside measurement.

## Metrics and limits

- `read_ns`: monotonic wall time around one typed `read_region`. Opening metadata, process startup and post-read value verification are excluded. It includes filesystem calls, codecs, allocation and region assembly; it is not pure disk latency.
- `peak_rss_bytes`: reader-process OS high-water memory, captured after the read and verification. It includes startup, runtime, metadata, result and transient allocations; it excludes the parent Python process, data generation and compiler. Windows uses [PeakWorkingSetSize](https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-process_memory_counters); Unix uses [`getrusage(RUSAGE_SELF)`](https://www.man7.org/linux/man-pages/man2/getrusage.2.html) (Linux KiB converted to bytes, macOS bytes). These are platform-specific process-resident metrics, not a portable heap-allocation counter or total system RAM consumption.
- `index_reads`, `index_bytes`, `payload_reads`, `payload_bytes`: completed explicit library range reads, **not physical disk transactions**. OS page-cache hits still count as library reads.
- `index_cache_hits`, `peak_cached_index_bytes`: index reuse and maximum retained raw index payload in one operation. Map/layout overhead and a newly read transient index are not included in this counter; RSS is measured separately.

The script does not clear filesystem caches. Discarding a trial warms the OS cache, not a persistent MoonBit cache. Results are not cold-disk measurements, and machine load, filesystem, storage device and compression ratio matter. Do not compare Windows working-set numbers directly with Linux/macOS RSS as if they were identical metrics.

## Index cache behavior

Native typed `read_region` uses a separate FIFO index cache for each call, defaulting to **16 MiB of index bytes and 64 entries**. An index fitting the caps is read and its optional CRC32C validated once while retained. Each selected entry still has offset/length bounds checked; only the selected payload is read. File existence, open, size and payload reads still occur per inner chunk, so caching does not remove all per-chunk filesystem overhead.

Configure a mutable `FileStore` with `FileStore::new(path, shard_index_cache_bytes=..., shard_index_cache_entries=...)`. Either zero disables caching; negative caps return `None`. Indices larger than the configured byte cap are used without retention; evicted indices must be read and validated again. Consolidated snapshot openers currently use the defaults.

There is no index persistence across region calls or element reads. Changed files are therefore re-read on the next call without reopening the `FileStore`. A size change also invalidates an entry during a call. This is **not a transaction or concurrent-writer snapshot**: callers must keep shard contents stable during one region read. Independent concurrent regions have independent caches and can collectively exceed a single operation's cap. No file handles or chunk payloads are cached.

`FileStore::shard_read_stats()` returns cumulative per-store counters; `reset_shard_read_stats()` resets them. Do not reset counters while another operation is running if you need meaningful totals.

## Interpretation

Index-heavy layouts are the intended optimization target. A small index or a slice touching one inner chunk may show little benefit or timing noise; a cache-on result is not automatically faster. Peak memory is reported for all cases rather than inferred from the cache cap. Rectangular reads still allocate the requested result and temporary decoded chunks, and some dtype wrappers allocate an additional conversion array. This work does not provide a streaming typed-array API, a full-array bounded-memory guarantee, HTTP-shard support, or broad dtype/codec/real-dataset performance coverage.
