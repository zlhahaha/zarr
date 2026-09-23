"""Generate small Zarr v2/v3 fixtures using zarr-python 3.4.0.

Run once from any working directory. Output goes only to
integration/fixtures/zarr-python; existing arrays are not overwritten.
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

    v2_u8 = create(
        "v2_u8", zarr_format=2, shape=(3, 4), chunks=(2, 2),
        dtype=np.dtype("u1"), fill_value=5, compressors=None, filters=None,
    )
    v2_u8[1, 2] = 7
    v2_u8[2, 3] = 9

    v3_u8 = create(
        "v3_u8", zarr_format=3, shape=(3, 4), chunks=(2, 2),
        dtype=np.dtype("u1"), fill_value=5, serializer=BytesCodec(),
        compressors=[], filters=[],
    )
    v3_u8[1, 2] = 7
    v3_u8[2, 3] = 9

    v2_f64_be = create(
        "v2_f64_be", zarr_format=2, shape=(3,), chunks=(2,),
        dtype=np.dtype(">f8"), fill_value=1.5, compressors=None, filters=None,
    )
    v2_f64_be[2] = 42.25

    v3_f32_le = create(
        "v3_f32_le", zarr_format=3, shape=(3,), chunks=(2,),
        dtype=np.dtype("f4"), fill_value=1.5,
        serializer=BytesCodec(endian="little"), compressors=[], filters=[],
    )
    v3_f32_le[2] = 42.25

    v3_i32_be = create(
        "v3_i32_be", zarr_format=3, shape=(3,), chunks=(2,),
        dtype=np.dtype("i4"), fill_value=-1,
        serializer=BytesCodec(endian="big"), compressors=[], filters=[],
    )
    v3_i32_be[2] = -200

    for name in ("v2_u8", "v3_u8", "v2_f64_be", "v3_f32_le", "v3_i32_be"):
        print(name)


if __name__ == "__main__":
    main()
