# Real CT conversion and PNG walkthrough

## Three-minute walkthrough

1. Show the [public CT source and fixed patch origins](../examples/zarr_npy_roi/README.md).
   The MoonBit consumer reads four patches with eight payload GETs.
2. Run the [batch example](../examples/zarr_npy_roi/README.md#prepare-a-batch-for-python).
   Open `verification.json` and `model-input.npy`. Show the float32
   `[4,1,16,16,16]` batch and the independent every-value check.
3. Show the [same-task write comparison](VOLUME_COMPARISON.md#c-order-write-optimization)
   against the published package. The separate conversion below demonstrates
   writing interoperable Zarr v3 and previewing a completed array.

## Zarr conversion and PNG preview

Run the numerical conversion, independent verification and native PNG preview
from a checkout. Requires Python 3.12+, moonc >= 0.10.20 and a native C compiler.

```sh
python -m pip install zarr==3.4.0 numpy==2.5.3
python scripts/demo_volume_pipeline.py --download --output-dir _build/ct-showcase
```

Use a new output directory for every run. `--download` explicitly permits
fetching the nine hash-pinned source objects; cached objects are always checked.
The first preview build also downloads published `mizchi/image@0.5.0` and its
dependencies. Run sequentially: source verification creates a temporary owned
`moon.work`. Windows interpreter selection is covered in
[real-volume reproduction](REAL_VOLUME_PIPELINE.md#reproduce).

The data is a public bonsai **CT** volume, not a microscopy acquisition. Native
MoonBit reads the ROI, normalizes to float32, computes its histogram and writes
v3 Zstd shards. Python orchestrates and checks results, rather than performing
the application's transformation.

The application then exports a completed array plane to RGBA8. A separate
native [preview module](../examples/zarr_preview/README.md) uses `mizchi/image`
to encode PNG. Separate modules isolate its newer async dependency from Zarr's
legacy runtime. This is an author-maintained example, not external adoption.

## Inspect the result

- `showcase.json`: overall verified/failed status and image hashes.
- `verification.json`: every-value array, metadata and completion verification.
- `verification-artifacts/*.zarr`: standard float32 shard arrays readable in Python.
- `aligned.png` / `nonaligned.png`: actual 128x128 and 123x124 CT slices.
- `*.rgba`: explicitly specified intermediate files between the two native modules.

The preview selects the first plane with the most nonzero voxels, records its
index, and applies no contrast enhancement. Python independently checks PNG
CRCs, decompresses/unfilters the image and verifies every RGB/alpha value against
the correct float32 array. Images complement the full numerical verification.

Suggested walkthrough: inspect the fixed source manifest and ROI, run the
command, open the verified arrays/images, then read the actual timing/request
records. See [completion checks](PIPELINE_COMPLETION.md) and the
[same-task comparison](VOLUME_COMPARISON.md) for failure semantics and costs.

The output preserves array dimension order; no physical-coordinate interpretation
or complete OME-NGFF export is claimed. Generic Zarr readers do not enforce the
application marker. Products from failed or interrupted runs must be checked
before use. Input data, generated arrays and images stay under ignored `_build/`.
