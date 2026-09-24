"""Generate independent Blosc fixtures with zarr-python 3.4.0."""

from pathlib import Path
import sys

PROJECT = Path(__file__).resolve().parents[1]
DEPS = PROJECT / ".interop-deps"
if DEPS.exists():
    sys.path.insert(0, str(DEPS))

import numpy as np
import numcodecs
import zarr
from zarr.codecs import BloscCodec, BytesCodec


def create(name: str, **kwargs):
    path = PROJECT / "integration" / "fixtures" / "zarr-python" / f"{name}.zarr"
    if path.exists():
        raise FileExistsError(path)
    return zarr.create_array(store=str(path), overwrite=False, **kwargs)


def main() -> None:
    if zarr.__version__ != "3.4.0":
        raise RuntimeError(f"expected zarr-python 3.4.0, got {zarr.__version__}")
    values = (np.arange(4096, dtype=np.uint16) % 64).astype("<u2")
    v2_lz4 = create(
        "v2_blosc_lz4_u16",
        zarr_format=2,
        shape=(4096,),
        chunks=(4096,),
        dtype=np.dtype("<u2"),
        fill_value=0,
        compressors=numcodecs.Blosc(cname="lz4", clevel=5, shuffle=1),
        filters=None,
    )
    v2_lz4[:] = values
    v3_lz4 = create(
        "v3_blosc_lz4_u16",
        zarr_format=3,
        shape=(4096,),
        chunks=(4096,),
        dtype=np.dtype("u2"),
        fill_value=0,
        serializer=BytesCodec(endian="little"),
        compressors=[BloscCodec(typesize=2, cname="lz4", clevel=5, shuffle="shuffle")],
        filters=[],
    )
    v3_lz4[:] = values
    v2_zstd = create(
        "v2_blosc_zstd_u16",
        zarr_format=2,
        shape=(4096,),
        chunks=(4096,),
        dtype=np.dtype("<u2"),
        fill_value=0,
        compressors=numcodecs.Blosc(cname="zstd", clevel=5, shuffle=0),
        filters=None,
    )
    v2_zstd[:] = values
    random_values = np.random.default_rng(42).integers(
        0, 65536, size=4096, dtype=np.uint16
    )
    v2_memcpy = create(
        "v2_blosc_memcpy_u16",
        zarr_format=2,
        shape=(4096,),
        chunks=(4096,),
        dtype=np.dtype("<u2"),
        fill_value=0,
        compressors=numcodecs.Blosc(cname="lz4", clevel=5, shuffle=1),
        filters=None,
    )
    v2_memcpy[:] = random_values
    many = create(
        "v2_blosc_lz4_multiblock_u16",
        zarr_format=2,
        shape=(8200,),
        chunks=(8200,),
        dtype=np.dtype("<u2"),
        fill_value=0,
        compressors=numcodecs.Blosc(
            cname="lz4", clevel=5, shuffle=1, blocksize=1024
        ),
        filters=None,
    )
    many[:] = (np.arange(8200, dtype=np.uint16) % 64).astype("<u2")
    f32 = create(
        "v3_blosc_lz4_f32",
        zarr_format=3,
        shape=(1024,),
        chunks=(1024,),
        dtype=np.dtype("f4"),
        fill_value=1.5,
        serializer=BytesCodec(endian="little"),
        compressors=[BloscCodec(typesize=4, cname="lz4", clevel=5, shuffle="shuffle")],
        filters=[],
    )
    f32[:] = np.full(1024, 1.5, dtype=np.float32)
    f32[1023] = np.float32(42.25)
    print("v2_blosc_lz4_u16 v3_blosc_lz4_u16 v2_blosc_zstd_u16 v2_blosc_memcpy_u16 v2_blosc_lz4_multiblock_u16 v3_blosc_lz4_f32")
    print("random first/last", int(random_values[0]), int(random_values[-1]))


if __name__ == "__main__":
    main()
