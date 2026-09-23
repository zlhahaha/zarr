"""Generate two independent zstd stores with zarr-python 3.4.0."""

from pathlib import Path
import sys

PROJECT = Path(__file__).resolve().parents[1]
DEPS = PROJECT / ".interop-deps"
if DEPS.exists():
    sys.path.insert(0, str(DEPS))

import numpy as np
import numcodecs
import zarr
from zarr.codecs import BytesCodec, ZstdCodec


def create(name: str, **kwargs):
    path = PROJECT / "integration" / "fixtures" / "zarr-python" / f"{name}.zarr"
    if path.exists():
        raise FileExistsError(path)
    return zarr.create_array(store=str(path), overwrite=False, **kwargs)


def main() -> None:
    if zarr.__version__ != "3.4.0":
        raise RuntimeError(f"expected zarr-python 3.4.0, got {zarr.__version__}")
    v2 = create(
        "v2_zstd_u8", zarr_format=2, shape=(3,), chunks=(2,),
        dtype=np.dtype("u1"), fill_value=5,
        compressors=numcodecs.Zstd(level=3), filters=None,
    )
    v2[2] = 9
    v3 = create(
        "v3_zstd_f32", zarr_format=3, shape=(3,), chunks=(2,),
        dtype=np.dtype("f4"), fill_value=1.5,
        serializer=BytesCodec(endian="little"),
        compressors=[ZstdCodec(level=3)], filters=[],
    )
    v3[2] = 42.25
    print("v2_zstd_u8\nv3_zstd_f32")


if __name__ == "__main__":
    main()
