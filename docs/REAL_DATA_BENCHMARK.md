# Real 3D tiled-read benchmark

This benchmark processes the `[0:128, 0:128, 0:128]` region of the public [OME-Zarr OpenSciVis bonsai dataset](https://github.com/InsightSoftwareConsortium/OMEZarrOpenSciVisDatasets). It is 2,097,152 actual uint8 voxels from eight Zstd-compressed objects, not synthetic fill data. The source array is `[256,256,256]`, with `[64,64,64]` chunks. Only the selected eight chunks and metadata are downloaded.

The harness computes an intensity histogram and coordinate-weighted checksum through `scan/remote.Source::open_u8`, verifies them independently with zarr-python 3.4.0 and NumPy 2.5.3, and records requests, bytes, elapsed time and OS reader-process peak resident memory. The histogram is a useful building block for intensity normalization, segmentation thresholds and imaging/AI input inspection; no ML framework or complete OME-NGFF metadata implementation is claimed.

## Reproduce

Use the GitHub checkout, MoonBit `moonc >= 0.10.20`, Python 3.12+ and a native C compiler. From the repository root:

```sh
python -m pip install zarr==3.4.0 numpy==2.5.3
python scripts/benchmark_real_scan.py --download --trials 3 --output _build/real-scan.json
```

Downloads require an explicit `--download`. The checked [manifest](../scripts/real_scan_manifest.json) pins the source URL, every object length and SHA-256. Changed upstream or corrupted local bytes fail verification. A cached repeat can omit `--download`; use a new output filename because reports are never overwritten. Original dataset bytes stay in ignored `_build/real-scan-data`, outside Git/Mooncakes. Source attribution belongs to the linked dataset; this repository distributes only hashes and original test code.

The Python oracle reads the same pinned objects using its own decoder. Every fresh release-built MoonBit process must produce the same 256-bin histogram, coordinate-weighted checksum, ordinary checksum `24039966`, voxel count and tile count. The report includes the toolchain, source digest, commit, raw trials and platform. It fails on incorrect results, not machine-dependent speed thresholds.

The optional **Real data scan** GitHub Actions workflow reproduces a shorter run and uploads its report. It is manually triggered so routine tests do not depend on public dataset availability. Deterministic scan, transport and mutation regressions still run in ordinary CI on every applicable backend.

## Measurement scope

After download and hash verification, a loopback HTTP server replays the original encoded objects without conversion. Fresh MoonBit processes measure the real remote decode/assembly/statistics path; Python generation/download/oracle allocations are outside reader RSS and elapsed time. RSS includes the MoonBit runtime, C dependencies, networking, metadata, temporary decode buffers and tile results. The server's memory is separate. Timer scope includes metadata opening and histogram processing, not compilation or initial public download.

The encoded object cache is disabled. A tile side of 32 revisits compressed chunks (64 payload requests per pass); side 64 aligns to chunks (8 requests). This deliberately exposes redundant decode/transfer work. Eight passes at side 64 test repeated traversal without consumer accumulation: 16 MiB of logical values processed, still one tile at a time. This is not a 16 MiB unique dataset.

Measured memory is a process high-water mark, not a portable cap. Three trials and this small 3D subset cannot establish memory bounds, whole-array throughput, WAN/cloud latency, production S3 behavior or performance on other codecs/shards/dtypes. This complements the larger synthetic local-file workloads in [BENCHMARKS.md](BENCHMARKS.md).

## Recorded Windows native 0.9.0 baseline

Source commit [`881c58c`](https://github.com/zlhahaha/zarr/commit/881c58c487cabd01d2e14afcfd34fdd171557527), moonc 0.10.20, three fresh processes per case; [complete raw report](benchmarks/windows-real-scan-20261109.json). Each case passed the independent histogram and coordinate-weighted checksum checks.

| Tile | Passes | Median elapsed | Max reader peak RSS | Payload GETs | All GETs |
|---|---:|---:|---:|---:|---:|
| 32³ | 1 | 579.94 ms | 8.09 MiB | 64 | 259 |
| 64³ | 1 | 88.16 ms | 8.15 MiB | 8 | 35 |
| 64³ | 8 | 740.04 ms | 8.25 MiB | 64 | 280 |

Alignment reduces payload refetch/decode work in this cache-disabled case. In this historical 0.9.0 run each hydration still probes array metadata; all-GET counts include those probes and absent metadata markers. Since 0.10.0, readers pin metadata once per opened scan instead. The harness now asserts exactly three metadata probes per pass and retains the same independent value checks and cache-disabled data path.

The repeated case processed eight times the logical values with a similar measured high-water mark; that observation is limited to these runs and does not prove bounded memory for arbitrary datasets or scan duration. Historical 0.5.0–0.6.0 speedup claims retain their original workload and version scope.

## 0.10.0 pinned-session run

Source [`95a9ceb`](https://github.com/zlhahaha/zarr/commit/95a9ceb0e7401f4a25bef0f9d6776d01f2fbfe06), same pinned data/toolchain, three fresh processes per case; [complete raw report](benchmarks/windows-real-scan-0100-20261109.json). All independent histograms and coordinate checks passed with object caching disabled.

| Tile | Passes | Median elapsed | Max reader peak RSS | Payload GETs | Metadata GETs | All GETs |
|---|---:|---:|---:|---:|---:|---:|
| 32³ | 1 | 469.10 ms | 8.06 MiB | 64 | 3 | 67 |
| 64³ | 1 | 71.65 ms | 8.16 MiB | 8 | 3 | 11 |
| 64³ | 8 | 571.46 ms | 8.26 MiB | 64 | 24 | 88 |

Total GET counts fall from 259/35/280 in the historical run to 67/11/88, while payload GETs remain 64/8/64. Each pass opens a new reader/session, hence three metadata probes per pass (including absent markers), with no per-tile metadata probes. The independent application test checks the same behavior for ordinary and sharded HTTP input. Shard index caching across tile hydrations has not been added.

These timings were measured in a later nonalternating run, not a paired statistical speed comparison against 0.9.0. Request elimination is directly counted; no universal throughput multiplier or memory reduction is claimed. Dataset, loopback/WAN and memory caveats above continue to apply.
