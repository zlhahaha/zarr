"""Generate an independent v3 checksummed-Zstd store with zarr-python 3.4.0."""

from pathlib import Path
import sys

PROJECT = Path(__file__).resolve().parents[1]
DEPS = PROJECT / ".interop-deps"
if DEPS.exists():
    sys.path.insert(0, str(DEPS))

import numpy as np
import zarr
from zarr.codecs import BytesCodec, ZstdCodec


def main() -> None:
    if zarr.__version__ != "3.4.0":
        raise RuntimeError(f"expected zarr-python 3.4.0, got {zarr.__version__}")
    path = PROJECT / "integration" / "fixtures" / "zarr-python" / "v3_zstd_checksum_u8.zarr"
    if path.exists():
        raise FileExistsError(path)
    array = zarr.create_array(
        store=str(path),
        overwrite=False,
        zarr_format=3,
        shape=(3,),
        chunks=(2,),
        dtype=np.dtype("u1"),
        fill_value=5,
        serializer=BytesCodec(),
        compressors=[ZstdCodec(level=3, checksum=True)],
        filters=[],
    )
    array[2] = 9
    print("v3_zstd_checksum_u8")


if __name__ == "__main__":
    main()
