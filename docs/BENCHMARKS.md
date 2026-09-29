# Native read latency and peak memory

This benchmark measures ordinary multi-chunk rectangular reads and v3 sharding-indexed reads. It is a reproducible synthetic workload, **not evidence that large-scale scientific workloads or terabyte arrays have been fully performance-validated**. No speed or RSS threshold is enforced in CI.

Version `0.4.0` adds [read resource budgets](RESOURCE_LIMITS.md); `0.5.0` adds [single-key filesystem write safety](WRITE_SAFETY.md). The documented benchmark selections fit the default budgets. The historical table measures `0.3.0`; the new section below measures a clean `0.5.0` baseline and optimized `0.6.0` implementation. Do not relabel the historical samples. Later hardening is verified separately by regression tests and the existing cross-platform read benchmark smoke profile; this benchmark does not measure write throughput or the overhead of staging/replacement. Policy caps are not substitutes for OS peak-memory measurements.

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

## 0.5.0 → 0.6.0 region-read comparison (2026-09-29)

A new clean baseline was built from [7e779cb](https://github.com/zlhahaha/zarr/commit/7e779cb3cef289e5e26301f53e928402e9212882), the published 0.5.0 source. The optimized binary was verified byte-for-byte against a rebuild at [0b16cfa](https://github.com/zlhahaha/zarr/commit/0b16cfa3426eb0219d5a0926e46d5e81cc2a5762). No budget was raised, index-cache setting changed, or value check removed. Both versions used the **same generated stores**, release toolchain and reader instrumentation.

The [alternating-version report](benchmarks/windows-native-050-vs-060-paired-20260929.json) retains five samples per version/case after one discarded trial. Baseline/optimized execution order alternates per trial; every element and checksum is checked, and index/payload counts and byte totals must match between versions. This mitigates simple version-order bias, but does not flush the OS cache or establish a statistical confidence interval.

Environment: Windows 11 build 22631, Intel Core Ultra 9 185H, approximately 31.42 GiB RAM, NTFS volume, moonc v0.10.14+7d59c7ec9, native release. Times below are median (min–max); peak memory is the maximum OS reader-process peak among retained trials. All cases use the existing operation-local index cache. The first four output 8 MiB logical data and touch 1089 chunks; the final case outputs 128 KiB and also touches 1089 inner chunks.

| Dataset | Extent | 0.5.0 ms (range) | Optimized ms (range) | Median ratio | Max peak MiB, old → new |
| --- | --- | ---: | ---: | ---: | ---: |
| v2_gzip | 2048² | 5236.81 (5195.57–5345.05) | 513.63 (504.92–524.52) | 10.2× | 15.00 → 14.90 |
| v3_raw | 2048² | 5256.33 (5232.87–5523.64) | 133.76 (129.46–146.43) | 39.3× | 14.66 → 14.67 |
| v3_gzip | 2048² | 5633.11 (5472.07–5783.13) | 524.74 (504.57–534.26) | 10.7× | 14.96 → 14.97 |
| v3_shard_gzip | 2048² | 5400.29 (5317.13–5671.39) | 477.26 (470.49–549.88) | 11.3× | 15.06 → 15.05 |
| v3_shard_index_stress | 256² | 173.16 (170.29–190.81) | 102.09 (97.60–113.33) | 1.7× | 6.93 → 6.93 |

These selected workloads show a substantial latency improvement, **not reduced peak memory** or a general speed ratio. Both versions still allocate the selection and per-chunk scratch/decoded/conversion buffers. No whole-array streaming guarantee, 3D/4D throughput measurement, real scientific dataset benchmark, cloud-read result or competitor comparison is implied.

### What changed and what remains

Source inspection found two per-element coordinate loops: the shared memory byte reader allocated coordinates, recomputed source/destination offsets and even constructed a discarded chunk key; native assembly then recomputed coordinates to scatter each piece again. The new helper computes strides once and visits last-axis runs with O(rank) scratch state. C-order rows copy contiguously; v2 F-order rows use the appropriate source stride. This optimization applies to **reads**, not the existing write loops.

The [clean baseline](benchmarks/windows-native-050-baseline-20260929.json), [shared-kernel-only stage](benchmarks/windows-native-060-memory-stage-20260929.json) and [full optimized run](benchmarks/windows-native-060-final-20260929.json) each retain 85 samples covering all 17 existing cases/modes. In those sequential full runs, the 2048² raw median was 5254.07 → 485.21 → 133.73 ms; gzip was 5686.53 → 819.17 → 522.50 ms. Removing the first coordinate loop accounted for most of the observed gain; removing native scatter coordinates improved it further. These are controlled implementation stages, **not a CPU profiler breakdown**. Filesystem open/size/read/close, gzip decoding, scratch stores and piece conversions remain; their individual costs were not isolated by a profiler, and no handle/payload reuse is claimed.

Provenance: the baseline report records a clean worktree. The stage/final full reports intentionally retain their original pre-commit HEAD plus nonempty worktree changes and source fingerprints; those HEAD fields alone must not be called release commits. The paired report links the actual immutable binaries to the baseline and verified optimized commits; the optimized SHA-256 is `86dbb77b07e1a65f5b8a385a939a92ef2d8b05202698511d89f2026fb28994a7`. Binary/dataset hashes, raw times, RSS and counters are preserved in all reports. Documentation/test additions do not affect the measured executable.

### Reproduce the version comparison on Windows PowerShell

From the current GitHub checkout, build the old source separately; these commands create a new ignored clone rather than changing your current checkout:

```powershell
git clone https://github.com/zlhahaha/zarr.git _build/bench-050-src
git -C _build/bench-050-src switch --detach 7e779cb3cef289e5e26301f53e928402e9212882
moon -C _build/bench-050-src update
moon -C _build/bench-050-src run --target native --release --build-only cmd/benchmark
moon run --target native --release --build-only cmd/benchmark
python scripts/benchmark_reads.py --trials 5 --work-dir _build/bench-compare-data --output _build/bench-new-full.json
python scripts/compare_region_reads.py --baseline _build/bench-050-src/_build/native/release/build/cmd/benchmark/benchmark.exe --optimized _build/native/release/build/cmd/benchmark/benchmark.exe --baseline-commit 7e779cb3cef289e5e26301f53e928402e9212882 --optimized-commit (git rev-parse HEAD) --work-dir _build/bench-compare-data --trials 5 --output _build/bench-paired.json
```

Requires the pinned Python dependencies from the reproduction section above. Use new data/report/clone paths on another run; generators and reports refuse overwrite. Record the actual commits used to build your binaries. The report labels are supplied by the caller; it records binary hashes but does not infer source provenance from executables.

## Historical 0.3.0 Windows run (2026-09-28)

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
