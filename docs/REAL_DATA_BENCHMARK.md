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

Recorded measurements are added after the source gate; historical 0.5.0–0.6.0 speedup claims retain their original workload and version scope.
