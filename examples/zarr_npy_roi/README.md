# Export a public Zarr region to NumPy

This author-maintained example installs `zlhahaha/zarr@0.10.0` from Mooncakes.
It reads a `16 × 16 × 16` uint8 region of the public
[bonsai CT volume](https://github.com/InsightSoftwareConsortium/OMEZarrOpenSciVisDatasets#bonsai)
at origin `[56,56,56]`. The crop crosses a source chunk boundary on each axis.
The MoonBit application materializes the 4,096 selected voxels as a C-order
`.npy` file and preserves their axis order and intensities. The small header
writer implements [NPY v1.0](https://numpy.org/doc/stable/reference/generated/numpy.lib.format.html#format-version-1-0)
for this example's three-dimensional uint8 output.

## Prepare a batch for Python

From the checkout root with Python 3.12+, `moonc >= 0.10.20`, and a native C
compiler:

```sh
python -m pip install zarr==3.4.0 numpy==2.5.3
python scripts/verify_zarr_npy_roi.py --download --batch --output-dir _build/zarr-npy-batch
```

MoonBit reads four `16³` patches from the same pinned array session and writes
`bonsai-patches.npy` in NDHW order. Python loads it, scales the values by 255,
adds a channel axis, and saves `model-input.npy` as float32 `[4,1,16,16,16]`
in NCDHW order. The verifier checks every value before and after preprocessing
against independently sliced zarr-python data. `verification.json` records
the ordered `[D,H,W]` origins, HTTP requests and bytes, shapes, and file hashes.
The four patches touch eight distinct data chunks and reuse encoded objects
within the session. The verified example runs through input preparation.

## Reproduce and verify

From the Zarr checkout root with Python 3.12+, `moonc >= 0.10.20`, and a native
C compiler:

```sh
python -m pip install zarr==3.4.0 numpy==2.5.3
python scripts/verify_zarr_npy_roi.py --download --output-dir _build/zarr-npy-roi
```

The verifier checks the SHA-256 of each source object against the repository
manifest, serves the compressed objects over loopback HTTP, and builds the
example with its registry dependency. It checks eight payload GETs and compares
the shape, dtype, and every value from `numpy.load` with an independent
zarr-python slice. The output directory contains `bonsai-roi.npy` and
`verification.json`. Choose a fresh output directory on reruns.

```python
import numpy as np

volume = np.load("_build/zarr-npy-roi/bonsai-roi.npy", allow_pickle=False)
print(volume.shape, volume.dtype)
# (16, 16, 16) uint8
```

For a direct export without Python, run from this example directory with a new
output path:

```sh
moon run --target native --release . -- https://ome-zarr-scivis.s3.us-east-1.amazonaws.com/v0.4/64x0/bonsai.ome.zarr/scale0/bonsai bonsai-roi.npy
```
