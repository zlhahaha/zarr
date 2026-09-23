"""Generate independent gzip/zlib Zarr fixtures with zarr-python 3.4.0.

The generator refuses to overwrite an existing fixture store.
"""

from pathlib import Path
import sys

PROJECT = Path(__file__).resolve().parents[1]
DEPS = PROJECT / ".interop-deps"
if DEPS.exists():
    sys.path.insert(0, str(DEPS))

import numpy as np
import numcodecs
import zarr
from zarr.codecs import BytesCodec, GzipCodec


def create(name: str, **kwargs):
    path = PROJECT / "integration" / "fixtures" / "zarr-python" / f"{name}.zarr"
    if path.exists():
        raise FileExistsError(path)
    return zarr.create_array(store=str(path), overwrite=False, **kwargs)


def main() -> None:
    if zarr.__version__ != "3.4.0":
        raise RuntimeError(f"expected zarr-python 3.4.0, got {zarr.__version__}")

    v2_gzip = create(
        "v2_gzip_u8", zarr_format=2, shape=(3,), chunks=(2,),
        dtype=np.dtype("u1"), fill_value=5,
        compressors=numcodecs.GZip(level=1), filters=None,
    )
    v2_gzip[2] = 9

    v2_zlib = create(
        "v2_zlib_f64", zarr_format=2, shape=(3,), chunks=(2,),
        dtype=np.dtype(">f8"), fill_value=1.5,
        compressors=numcodecs.Zlib(level=1), filters=None,
    )
    v2_zlib[2] = 42.25

    v3_gzip = create(
        "v3_gzip_i32", zarr_format=3, shape=(3,), chunks=(2,),
        dtype=np.dtype("i4"), fill_value=-1,
        serializer=BytesCodec(endian="big"),
        compressors=[GzipCodec(level=1)], filters=[],
    )
    v3_gzip[2] = -200

    for name in ("v2_gzip_u8", "v2_zlib_f64", "v3_gzip_i32"):
        print(name)


if __name__ == "__main__":
    main()
