# N-dimensional interoperability

Version `0.6.0` adds explicit independent 3D image-volume and 4D time/space/feature-tensor checks. These are storage-format tests, not a tensor-computation engine, image format reader, ML framework integration, or a claim of real-dataset adoption.

## Coverage

Eight new zarr-python 3.4.0 stores bring the committed inventory to **51**; eight new MoonBit-written stores bring reverse verification to **40**. The N-D reverse checks run on Linux, macOS and Windows native; the older 32 reverse stores run on Linux. Portable memory regressions also run on wasm-gc.

| Direction | Data | Formats and layouts |
| --- | --- | --- |
| Python → MoonBit | 3D `uint16`, shape `[5,7,9]`, inner chunks `[2,3,4]` | v2 C raw; v2 F big-endian gzip; v3 little-endian zstd; v3 big-endian gzip inside end-index CRC32C shards |
| Python → MoonBit | 4D `float32`, shape `[3,5,7,4]`, inner chunks `[2,2,3,3]` | v2 C gzip; v2 F big-endian zlib; v3 big-endian raw; v3 little-endian zstd inside start-index CRC32C shards |
| MoonBit → Python | Same 3D volume | v2 C raw; v2 F big-endian gzip; v3 little-endian zstd; v3 big-endian gzip |
| MoonBit → Python | Same 4D tensor | v2 C gzip; v2 F big-endian zlib; v3 big-endian raw; v3 little-endian zstd |

The generator writes only `[1:5,1:4,1:9]` of the 3D volume and `[1:3,1:3,1:7,1:4]` of the 4D tensor. This leaves both untouched elements and entirely absent chunks, reaches non-divisible edge chunks, and crosses many chunk boundaries. Fills are `60000` and `-1.5` respectively. Coordinate-weighted integer/quarter-float formulas distinguish axes and byte order exactly; no float tolerance hides errors. An existing edge chunk is then overwritten with a `+7` value.

MoonBit reads every full-array value and non-aligned subregions, the rewritten edge, missing fills, an empty boundary region and an invalid out-of-bounds region. Stores are reopened. The reverse generator writes via `write_region` plus an element overwrite, reopens and checks every value; Python independently checks complete values, slices, shape, chunks, dtype, endian, order and compressor metadata. Sharded writes remain unsupported; the reverse stores are ordinary chunks.

`copy_region_spans` has differential tests against the original element-coordinate reference for rank 0–4, C/F ordering, asymmetric boxes and thin runs. Invalid geometry/overflow must invoke no copy callback. Scalar/empty and portable compressed N-D regressions preserve the existing resource-budget checks and fill semantics. This does not exhaust every dtype/rank/codec combination.

## Reproduce from a GitHub checkout

Requires `moonc >= 0.10.14`, native C support and Python 3.12+:

```sh
moon update
python -m pip install zarr==3.4.0 numpy==2.5.3
moon test --target native --deny-warn
moon test --target wasm-gc --deny-warn
moon run --target native cmd/nd_demo
moon run --target native cmd/nd_interop _build/nd-roundtrip-1
python scripts/verify_nd_roundtrip.py --root _build/nd-roundtrip-1
```

The usage example creates and removes its own temporary group with a compressed 3D volume and 4D tensor. Expected output:

```text
Zarr N-D: 3D volume (96 values), 4D features (72 values), reopen and fills verified
```

The reverse generator preserves output stores and refuses to overwrite existing metadata. Choose a new output root for another run. No need to delete older generated data. To regenerate the Python fixtures independently without touching the committed inventory:

```sh
python scripts/generate_nd_fixtures.py --output _build/nd-python-1
```

These Python scripts/committed test data require the GitHub checkout, not just the Mooncakes library archive. The packaged `cmd/nd_demo` and public typed APIs do not require Python. V2 F-order tests use explicit metadata: the convenience creation helpers currently produce C-order arrays, while opening and modifying existing F-order arrays is supported.

## Application boundary

These tests demonstrate the storage operations needed for cropped image volumes, selected time/space windows and precomputed feature tensors. They do not validate OME-Zarr metadata, CF/xarray conventions, training throughput, cloud deployment, GPUs, arbitrary strided/negative-step indexing or whole-array streaming. Performance measurements in [BENCHMARKS.md](BENCHMARKS.md) are synthetic **2D uint16** workloads; 3D/4D correctness should not be described as measured 3D/4D performance.
