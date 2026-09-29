# Native read latency and peak memory

This benchmark measures ordinary multi-chunk rectangular reads and v3 sharding-indexed reads. It is a reproducible synthetic workload, **not evidence that large-scale scientific workloads or terabyte arrays have been fully performance-validated**. No speed or RSS threshold is enforced in CI.

Version `0.4.0` adds [read resource budgets](RESOURCE_LIMITS.md). The documented benchmark selections fit their defaults. The full Windows table below measures the recorded `0.3.0` implementation baseline, not newly measured `0.4.0` performance; budget hardening is verified separately by regression tests and the existing cross-platform benchmark smoke profile. Policy caps are not substitutes for OS peak-memory measurements.

## Reproduce

Requires `moonc >= 0.10.14`, a native C toolchain, Python 3.12 or newer, and the pinned independent data generator:

Use the GitHub source checkout (clone it as described in [README](../README.md#install-and-try)). The Mooncakes library archive does not include the Python benchmark scripts; run the commands below from the repository root:

```sh
moon update
python -m pip install zarr==3.4.0 numpy==2.5.3
python scripts/benchmark_reads.py --trials 5 --work-dir _build/bench-data --output _build/bench-results.json
```

The script builds only `cmd/benchmark` in native **release** mode, creates new stores, and refuses to overwrite existing datasets or reports. To repeat against the same generated data, use `--reuse` with a new report path. Native CI on Linux, macOS and Windows uses the smaller smoke profile:

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

## Recorded Windows run (2026-09-28)

The [complete JSON report](https://github.com/zlhahaha/zarr/blob/main/docs/benchmarks/windows-native-20260928.json) records all 85 retained samples, input SHA-256 hashes, binary/source fingerprints and the measured implementation commit [7cb502e](https://github.com/zlhahaha/zarr/commit/7cb502ee04d7f864b58fce3f9d8d33f97a908c76). Environment: Windows 11 (build 22631), Intel Core Ultra 9 185H (16 cores / 22 logical processors), approximately 31.42 GiB OS-reported physical RAM, NTFS data volume, native release build, moonc v0.10.14+7d59c7ec9. Storage-device model and cold-cache performance were not measured. No benchmark speed threshold was applied.

Times are medians of five trials; the range is min–max of those trials. Memory is the **maximum OS peak** across the five fresh processes, not the median heap size. All output values and cached/uncached checksums passed verification.

| Dataset | Extent | Index cache | Median ms | Min–max ms | Max peak MiB | Index reads |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| v2_gzip | 256² | on | 281.87 | 280.87–291.59 | 6.51 | 0 |
| v2_gzip | 1024² | on | 1255.05 | 1237.77–1277.78 | 8.63 | 0 |
| v2_gzip | 2048² | on | 5110.47 | 5090.21–5204.58 | 14.99 | 0 |
| v3_raw | 256² | on | 302.04 | 296.18–308.58 | 6.37 | 0 |
| v3_raw | 1024² | on | 1330.82 | 1284.02–1349.65 | 8.34 | 0 |
| v3_raw | 2048² | on | 5305.80 | 5128.15–5359.06 | 14.69 | 0 |
| v3_gzip | 256² | on | 94.40 | 92.92–97.47 | 6.52 | 0 |
| v3_gzip | 1024² | on | 1442.97 | 1441.23–1454.55 | 8.58 | 0 |
| v3_gzip | 2048² | on | 5709.63 | 5647.61–5719.89 | 15.02 | 0 |
| v3_shard_gzip | 256² | off | 93.04 | 88.60–98.35 | 6.52 | 25 |
| v3_shard_gzip | 256² | on | 91.70 | 90.27–98.55 | 6.55 | 1 |
| v3_shard_gzip | 1024² | off | 1469.61 | 1438.36–1491.21 | 8.59 | 289 |
| v3_shard_gzip | 1024² | on | 1431.07 | 1423.61–1459.63 | 8.59 | 9 |
| v3_shard_gzip | 2048² | off | 5675.05 | 5515.76–5982.88 | 15.04 | 1089 |
| v3_shard_gzip | 2048² | on | 5627.52 | 5410.96–5638.59 | 15.05 | 25 |
| v3_shard_index_stress | 256² | off | 2708.24 | 2696.56–2823.19 | 6.95 | 1089 |
| v3_shard_index_stress | 256² | on | 177.90 | 172.92–180.07 | 6.96 | 1 |

The index-heavy case improved by **15.2× in this run**, with index reads falling from 1089 to 1 (285479172 to 262148 index bytes). Its payload reads remain 1089; no payload caching is claimed. Peak process memory was effectively unchanged. The ordinary gzip-shard cases show only small timing differences, not a demonstrated broad speedup. In particular, differences of a few percent should not be interpreted as statistically established performance improvements from five trials.

The 2048² results allocate an 8 MiB logical output and touch 1089 chunks; peak reader memory here is about 15 MiB for gzip and 14.7 MiB for raw. This verifies those synthetic selections only. Smaller-case timing variability, OS file caching, filesystem calls per chunk and result assembly remain material. There is no claim of throughput parity with zarr-python, optimized ndarray engines or cloud readers; no independent competitor timing was performed.
