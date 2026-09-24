"""Generate full-range int64/uint64 fixtures with zarr-python 3.4.0.

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
        "v2_i64_be", zarr_format=2, shape=(3,), chunks=(2,),
        dtype=np.dtype(">i8"), fill_value=-9223372036854775807,
        compressors=None, filters=None,
    )
    v2[2] = 9223372036854775807

    v3 = create(
        "v3_u64_le_zstd", zarr_format=3, shape=(3,), chunks=(2,),
        dtype=np.dtype("u8"), fill_value=18446744073709551615,
        serializer=BytesCodec(endian="little"),
        compressors=[ZstdCodec(level=3)], filters=[],
    )
    v3[2] = 18446744073709551614
    print("v2_i64_be, v3_u64_le_zstd")


if __name__ == "__main__":
    main()
