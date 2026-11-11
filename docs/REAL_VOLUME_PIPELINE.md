# Real CT volume conversion

This example connects the existing hash-pinned [bonsai CT dataset](https://github.com/InsightSoftwareConsortium/OMEZarrOpenSciVisDatasets#bonsai) to the [volume application](../examples/volume_pipeline/README.md). Bonsai is a CT scan of a tree, not a microscopy acquisition. The application is maintained by this library's author; it is not evidence of an external adopter.

```text
Public OME-Zarr CT objects (fixed SHA-256 manifest)
  → original compressed objects replayed over local HTTP
  → native MoonBit ROI reader
  → float32(value) / float32(255) + intensity histogram
  → local Zarr v3, Zstd-compressed whole shards
  → independent zarr-python decode and every-value verification
```

Python orchestrates the experiment and checks results; the transformation and shard writes run in MoonBit without a Python runtime in the application. The output is a standard Zarr numerical array with processing provenance. It preserves array dimension order without interpreting physical coordinates and does not claim complete OME-NGFF metadata export.

## Reproduce

Use `moonc >= 0.10.20`, a native C compiler and Python 3.12+ compatible with the pinned packages. From the repository root:

```sh
python -m pip install zarr==3.4.0 numpy==2.5.3
python scripts/verify_real_volume_pipeline.py --download --output _build/real-volume-registry.json
```

The default builds the application's pinned **published** `zlhahaha/zarr@0.10.0` dependency and rejects ancestor workspace overrides. To check the current source separately:

```sh
python scripts/verify_real_volume_pipeline.py --source --output _build/real-volume-source.json
```

Run these commands sequentially. Source mode temporarily creates an exclusively owned root `moon.work`, then removes it; do not run other Moon commands concurrently. A second run must use a new report filename: existing reports and artifact directories are never overwritten. Use `--trials 1` for a shorter smoke check; default is three measured trials after one warmup per ROI. Each trial launches a new release executable and writes a fresh output.

The cached input directory is shared with [real scan measurements](REAL_DATA_BENCHMARK.md). `--download` allows fetching only missing objects; every cached/downloaded object must match the [existing manifest](../scripts/real_scan_manifest.json). Without that flag, missing data fails. Source data stays under ignored `_build/real-scan-data`; a changed upstream object or corrupt cache fails rather than silently switching datasets.

On Windows, use the Python interpreter into which the dependencies were installed. For an existing project-local `.interop-deps` installation, for example:

```powershell
$env:PYTHONPATH = (Join-Path (Get-Location) '.interop-deps')
& 'C:\path\to\python.exe' scripts/verify_real_volume_pipeline.py --download --output _build/real-volume-registry.json
```

## What is verified

| Case | Input origin | ROI shape | Values checked per trial | Output shards |
| --- | --- | --- | ---: | ---: |
| Aligned | `[0,0,0]` | `[128,128,128]` | 2,097,152 | 256 |
| Nonaligned | `[1,2,3]` | `[125,124,123]` | 1,906,500 | 256 |

Both selections lie entirely within the eight hash-pinned source chunks. The Python reference only reads that known region, avoiding accidental fill reads from the unavailable remainder of the 256³ source array.

For every warmup and measured trial, the verifier checks:

- Exact equality of every output float32 value to the independently decoded and normalized input (zero tolerance).
- Shape, dtype, Zarr version, `[2,16,16]` inner chunks, `[8,32,32]` outer shards and Zstd level 3.
- The histogram, source checksum, voxel count, processing attributes and ROI mapping.
- Presence of every expected shard file, including partial edge shards and fill-only shards.
- Exactly three metadata probes per scan, successful payload responses and the expected eight distinct input objects.

Only after **all** trials pass does the script create the final JSON report with `status: verified`. Nonzero exit status means failure. It retains a sibling `REPORT-STEM-artifacts/` directory containing converted `.zarr` outputs, stdout/stderr, per-trial request records and `verification-status.json`. Paths in each sample are relative to that artifact directory.

The application now writes its own `pipeline-status.json` before creating array metadata and changes it from `incomplete` to `complete` only after all shards and provenance are written. `volume_pipeline --check OUTPUT` rejects missing/incomplete/malformed markers or missing/nonregular shard paths. It exclusively creates the destination, so an interrupted output cannot be accidentally reused. See [failure checks](PIPELINE_COMPLETION.md).

There is still no transaction/resume protocol: generic Zarr readers ignore this application marker and may interpret absent chunks as fills. Do not consume products from failed or interrupted experiments. The marker, final verified report and run status describe completion/verification at run time, not integrity after later file modification.

## Measurement boundaries

The wall timer surrounds a direct release-executable invocation and includes process launch, HTTP metadata and ROI reads, decoding, normalization, histogram, compression, shard writes, provenance and completion markers. Compilation, first download, Python reference decoding and Python verification are outside the timer. The application additionally records internal stage times and OS reader-process peak RSS; the HTTP server and oracle run in the separate Python verifier process and are excluded from reader RSS. Historical first-batch reports without application instrumentation retain `peak_rss_bytes: null`.

Reports retain every measured elapsed time, median/min/max, HTTP metadata/payload request counts, actual response-body byte counts, distinct object counts and output file sizes. The application's default cache policy applies: count actual requests instead of assuming one transfer per processing tile. Filesystem and OS caches are not forcibly evicted. This is a small fixed CT ROI over loopback, not WAN/cloud latency, cold-storage throughput, a general speedup or a total-memory bound. This verifier measures one implementation at a time; the separate [paired comparison](VOLUME_COMPARISON.md) adds the Python performance reference.

The optional manual **Real data scan** workflow runs both source and registry modes, a paired comparison smoke and the PNG showcase, uploading reports/request records/logs. Source objects, converted volume directories and PNGs are not uploaded by that workflow. Ordinary CI remains independent of the public dataset service and runs generated-data application failure checks.

For complete-task comparison evidence and limits, see [VOLUME_COMPARISON.md](VOLUME_COMPARISON.md).
