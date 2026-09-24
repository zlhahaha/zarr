"""Generate non-finite fill fixtures with zarr-python 3.4.0.

Existing fixture directories are never overwritten.
"""

from pathlib import Path
import sys

PROJECT = Path(__file__).resolve().parents[1]
DEPS = PROJECT / ".interop-deps"
if DEPS.exists():
    sys.path.insert(0, str(DEPS))

import numpy as np
import zarr
from zarr.codecs import BytesCodec


def create(name: str, **kwargs):
    path = PROJECT / "integration" / "fixtures" / "zarr-python" / f"{name}.zarr"
    if path.exists():
        raise FileExistsError(f"fixture already exists: {path}")
    path.parent.mkdir(parents=True, exist_ok=True)
    return zarr.create_array(store=str(path), overwrite=False, **kwargs)


def main() -> None:
    if zarr.__version__ != "3.4.0":
        raise RuntimeError(f"expected zarr-python 3.4.0, got {zarr.__version__}")

    v2 = create(
        "v2_f64_nan", zarr_format=2, shape=(3,), chunks=(2,),
        dtype=np.dtype(">f8"), fill_value=np.nan,
        compressors=None, filters=None,
    )
    v2[2] = 42.25

    v3 = create(
        "v3_f32_neg_inf", zarr_format=3, shape=(3,), chunks=(2,),
        dtype=np.dtype("f4"), fill_value=-np.inf,
        serializer=BytesCodec(endian="little"), compressors=[], filters=[],
    )
    v3[2] = 1.25
    print("v2_f64_nan, v3_f32_neg_inf")


if __name__ == "__main__":
    main()
