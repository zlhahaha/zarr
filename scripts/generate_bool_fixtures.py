"""Generate independent boolean fixtures with zarr-python 3.4.0.

The script refuses to overwrite committed fixtures.
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


def main():
    if zarr.__version__ != "3.4.0":
        raise RuntimeError(f"expected zarr-python 3.4.0, got {zarr.__version__}")

    v2 = create(
        "v2_bool", zarr_format=2, shape=(3, 4), chunks=(2, 2),
        dtype=np.dtype("bool"), fill_value=True, compressors=None, filters=None,
    )
    v2[1, 2] = False
    v2[2, 3] = False

    v3 = create(
        "v3_bool", zarr_format=3, shape=(3, 4), chunks=(2, 2),
        dtype=np.dtype("bool"), fill_value=True, serializer=BytesCodec(),
        compressors=[], filters=[],
    )
    v3[1, 2] = False
    v3[2, 3] = False

    print("v2_bool")
    print("v3_bool")


if __name__ == "__main__":
    main()
