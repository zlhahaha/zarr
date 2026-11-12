# Real CT conversion benchmark

## C-order write optimization

The checkout's C-order writer copies contiguous row spans into each inner
chunk. To measure the change against the published 0.10.0 package, build the
same volume application against both library versions and run alternating pairs:

```sh
python -m pip install zarr==3.4.0 numpy==2.5.3
python scripts/benchmark_volume_pipeline.py --registry-baseline --download --trials 5 --output _build/paired-registry.json
```

The benchmark uses Python to verify every output value from both builds. It
records executable hashes, elapsed times, peak RSS and the fixed input manifest.
The standard Python comparison remains available through the command below.

The uninstrumented Windows run compared the published package with source
commit `6da0262`. Five paired rounds per ROI produced byte-identical output
trees. The wall medians include process launch. The
[measured samples](benchmarks/windows-ct-span-vs-registry-20261112.json)
include all 20 conversions, executable hashes, and matching output-tree
hashes for each pair.

| ROI | Published 0.10.0 | Source with span writes | Lower wall time |
| --- | ---: | ---: | ---: |
| Aligned | 4.93 s | 2.25 s | 54.4% |
| Nonaligned | 6.06 s | 3.47 s | 42.8% |

The maximum peak RSS increase was 0.17 MiB on this host.

In the initial Windows experiment, enabling only C-order span writes reduced
median wall time from **5.36 to 2.29 s** for the aligned ROI and from **6.13 to
3.43 s** for the nonaligned ROI. The largest observed peak RSS increase was
0.11 MiB. These five-pair results came from an instrumented source build with
the write optimization toggled. Each pair produced byte-identical output trees.

## Original 0.10.0 source versus zarr-python

The Windows run used two hash-pinned CT regions and five alternating measured
pairs per region. MoonBit took longer and used less peak resident memory in this
workload. All 24 conversions, including warmups, passed independent every-value
and completion checks. [Raw results](benchmarks/windows-paired-volume-20261111.json)

| ROI / implementation | Process wall median (ms) | Max RSS (MiB) | Open (ms) | Hydrate (ms) | Decode (ms) | Process (ms) | Write (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Aligned / moonbit | 4,869.64 | 8.74 | 2.66 | 22.77 | 1,561.51 | 4.74 | 3,246.50 |
| Aligned / python | 2,205.85 | 55.44 | 29.98 | 45.09 | 181.25 | 14.96 | 1,237.65 |
| Nonaligned / moonbit | 6,208.05 | 8.74 | 3.06 | 25.50 | 2,859.58 | 4.60 | 3,258.59 |
| Nonaligned / python | 2,132.25 | 56.88 | 28.51 | 41.28 | 217.19 | 12.95 | 1,174.56 |

Each measured process made 11 GETs (3 metadata and 8 payload) and received
301,835 response-body bytes. Decode and shard writes accounted for most of
MoonBit's elapsed time. Stage medians are calculated independently.

## Task

Both paths use the same pinned encoded objects replayed over loopback HTTP,
compute a 256-bin histogram, and normalize each voxel as
`float32(value) / float32(255)`. The aligned region is `[0,0,0] + [128,128,128]`.
The nonaligned region is `[1,2,3] + [125,124,123]`.

Both use `[8,32,32]` processing tiles, an encoded-object cache and a v3 layout
with float32 values, inner chunks `[2,16,16]`, outer shards `[8,32,32]` and
Zstd level 3. Each writes all 256 shards, including edge and fill-only
shards, with provenance and an application completion marker. The Python
reference uses NumPy and zarr-python, with a local store that stages writes,
flushes data with `fsync` and replaces one key at a time. The byte encodings,
index settings, runtimes and filesystem call sequences can differ.

## Run from a checkout

```sh
python -m pip install zarr==3.4.0 numpy==2.5.3
python scripts/benchmark_volume_pipeline.py --download --trials 5 --output _build/paired-volume.json
```

Use `--download` to fetch missing objects. Cached objects always undergo hash
verification. Choose a new output path and run the source workspace build
sequentially with other Moon commands. The script warms each path once per ROI,
then alternates AB/BA order. Each trial starts a new process and writes a new
output directory. Verification checks every value, metadata, all shards and
completion before the script writes its report. CI uses one pair for a smoke check.

## Measurement boundaries

| Metric | Scope |
| --- | --- |
| Wall time | Process launch to exit, including runtime startup and Python imports. Compilation, source download and independent verification happen outside this interval. |
| Open | Metadata probes, parsing and array or reader setup. |
| Hydrate | Encoded-object fetch, cache lookup and staging. MoonBit includes reader overhead. |
| Decode | Codec work and ROI assembly, including typed array setup. |
| Process | Normalization, histogram and checksum. |
| Write | Compression, shard indexing, filesystem writes, data sync, replacement, provenance and completion. |
| Peak RSS | OS process high-water mark. Includes each runtime and its allocations. The HTTP server and independent oracle run in the parent Python process. |

MoonBit measures synchronous decode inside the remote reader and subtracts it
from the enclosing read interval. Local-file reads combine I/O and decode.
Filesystem caches remain in their normal operating state. The measurement
covers a fixed loopback workload with a task-specific Python reference. Results
apply to this ROI, output layout, machine and toolchain.
