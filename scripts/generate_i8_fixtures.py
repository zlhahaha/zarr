"""Generate signed 8-bit Zarr fixtures with zarr-python 3.4.0.

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
from zarr.codecs import BytesCodec, ZstdCodec


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
        "v2_i8", zarr_format=2, shape=(3,), chunks=(2,),
        dtype=np.dtype("i1"), fill_value=-5,
        compressors=None, filters=None,
    )
    v2[1:3] = np.array([-128, 127], dtype=np.int8)

    v3 = create(
        "v3_i8_zstd", zarr_format=3, shape=(3,), chunks=(2,),
        dtype=np.dtype("i1"), fill_value=-5,
        serializer=BytesCodec(), compressors=[ZstdCodec(level=3)], filters=[],
    )
    v3[1:3] = np.array([-128, 127], dtype=np.int8)
    print("v2_i8, v3_i8_zstd")


if __name__ == "__main__":
    main()
