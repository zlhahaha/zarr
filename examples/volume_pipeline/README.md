# Cropped volume normalization

An independent native MoonBit module using the published `zlhahaha/zarr@0.10.1` library. It reads a 3D uint8 array from local files, HTTP or S3, crops a rectangular ROI, divides intensities by 255, and writes float32 Zstd-compressed v3 shards. It also computes a 256-bin histogram and checksum. This is an application maintained in this repository, not a claim of an external adopter.

This demonstrates data preparation for imaging tools, model inputs and scientific data conversion. No ndarray arithmetic framework, training loop, clinical interpretation or full OME-NGFF implementation is required or claimed.

## Run

Requires `moonc >= 0.10.20` with a native C compiler. From this directory:

```sh
moon update
moon check --target native --deny-warn
moon build --target native
moon run --target native . INPUT ARRAY_PATH OUTPUT O0 O1 O2 N0 N1 N2
```

The manifest directly pins both `zlhahaha/zarr@0.10.1` and `moonbitlang/async@0.20.3`. `INPUT` is a local store root, HTTP root URL or `s3://bucket/prefix`. `ARRAY_PATH` is relative to that root (use `""` for a root array). `OUTPUT` must be a new local array root. Origins and extents follow the input array's dimension order; this program preserves that order without interpreting axes or physical coordinates.

For example, with a local input of at least `[10,36,38]`:

```sh
moon run --target native . input.zarr "" output.zarr 1 2 3 9 34 35
```

The output shape is `[9,34,35]`, dtype float32, inner chunks `[2,16,16]` and outer shards `[8,32,32]`. Every output voxel equals the corresponding uint8 input divided by 255. This example writes eight edge-clipped shards and prints JSON with `voxels=10710`, `shards=8`, `input_checksum` and `histogram`. Attributes record the operation and original ROI.

HTTP/S3 shard inputs need a server supporting strict Range responses. For S3 set `ZARR_REGION` (default `us-east-1`); optionally set **both** `ZARR_ACCESS_KEY` and `ZARR_SECRET_KEY`, plus `ZARR_SESSION_TOKEN` for temporary credentials. No default credential chain is read. `ZARR_ENDPOINT` selects a custom path-style service. Credentialed plaintext endpoints require explicit `ZARR_ALLOW_INSECURE_HTTP=true`; use that only for an isolated test service. Keep credentials in the environment, outside commands/files/logs.

Tiles are processed sequentially and discarded. Each read and whole-shard write still buffers data; caches and intermediate values also consume memory. There is no aggregate-RAM bound. Metadata is pinned for a remote scan, not a snapshot of changing objects. Input must remain stable during processing.

The first tile is read before output creation. Invalid initial ROI/dtype fails without an output array. The output directory is then created exclusively (its parent must exist), and `pipeline-status.json` is set to `incomplete` before metadata or shards are written. Only successful completion of every shard and provenance write sets it to `complete`. Any existing directory is rejected, including a previous incomplete run. Choose a fresh destination.

Before consuming output, run `moon run --target native . --check OUTPUT`. This checks the completion marker, matching metadata and expected shard files. Late read/write failure or process termination leaves a product that this checker rejects. Generic Zarr readers ignore the marker; it is not a transaction, resume protocol, post-edit integrity proof or power-loss guarantee. See [completion checks and real fault tests](../../docs/PIPELINE_COMPLETION.md).

JSON stdout also records monotonic open/hydration/decode/processing/write timings and OS process peak RSS. Remote decoding is timed separately from encoded hydration; local filesystem reads cannot separate their I/O from decoding and report that explicitly. Write time includes compression, index creation, data synchronization and replacement. The measurement C stub in `metrics/` reuses this repository's original `cmd/metrics` instrumentation.

To export a completed normalized array slice, use `moon run --target native . --export-slice OUTPUT SLICE_INDEX NEW_RGBA`. A [separate native image module](../zarr_preview/README.md) encodes that RGBA8 plane to PNG, isolating its newer async dependency.

## Reproduce without your own input

For a fixed **real CT dataset**, two ROI conversions, every-value Python
verification, retained Zarr outputs and full-process request/timing records, see
[real CT volume conversion](../../docs/REAL_VOLUME_PIPELINE.md). The commands
below exercise generated data and transport/error regressions separately.

From the repository root, install the pinned Python oracle and run:

```sh
python -m pip install zarr==3.4.0 numpy==2.5.3
python scripts/verify_volume_pipeline.py --output _build/volume-registry.json
```

This generates deterministic 3D data and verifies **every output value**, histogram, edge shard, provenance, overwrite rejection and invalid ROI behavior, using local and HTTP v2/v3/ v3-sharded sources. The default actually downloads the registry dependency and rejects a checkout override. Expected output includes six `volume pipeline verified ...` lines, each checking 10710 values and eight shards. Fixtures/results are temporary; no scientific dataset bytes are distributed.

Maintainers can run `python scripts/verify_volume_pipeline.py --source` before publication; it creates an exclusive temporary root `moon.work`, tests this checkout and removes the workspace on exit. Do not run other Moon commands concurrently with that source check. This mode is explicitly different from registry verification. The real private [MinIO gate](../../docs/REMOTE.md#reproduce-private-minio-integration) additionally uploads a 3D sharded input, reads it through authenticated S3 and verifies the same pipeline output. Production AWS authorization is not certified by that test.
