"""Generate signed-16-bit Zarr fixtures with zarr-python 3.4.0."""

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
        raise FileExistsError(path)
    return zarr.create_array(store=str(path), overwrite=False, **kwargs)


def main() -> None:
    if zarr.__version__ != "3.4.0":
        raise RuntimeError(f"expected zarr-python 3.4.0, got {zarr.__version__}")
    v2 = create(
        "v2_i16_be", zarr_format=2, shape=(3,), chunks=(2,),
        dtype=np.dtype(">i2"), fill_value=-1234,
        compressors=None, filters=None,
    )
    v2[2] = -32768
    v3 = create(
        "v3_i16_le_zstd", zarr_format=3, shape=(3,), chunks=(2,),
        dtype=np.dtype("i2"), fill_value=-1234,
        serializer=BytesCodec(endian="little"),
        compressors=[ZstdCodec(level=3)], filters=[],
    )
    v3[2] = 32767
    print("v2_i16_be\nv3_i16_le_zstd")


if __name__ == "__main__":
    main()
