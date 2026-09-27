"""Generate independent Zarr v3 sharding fixtures with zarr-python 3.4.0.

Each target is new and this script refuses to overwrite a previous fixture.
"""

from pathlib import Path
import sys

PROJECT = Path(__file__).resolve().parents[1]
DEPS = PROJECT / ".interop-deps"
if DEPS.exists():
    sys.path.insert(0, str(DEPS))

import numpy as np
import zarr
from zarr.codecs import BloscCodec, BytesCodec, Crc32cCodec, GzipCodec, ShardingCodec

ROOT = PROJECT / "integration" / "fixtures" / "zarr-python"


def new_array(name: str, *, shard_codec: ShardingCodec, **kwargs):
    path = ROOT / f"{name}.zarr"
    if path.exists():
        raise FileExistsError(f"refusing to overwrite {path}")
    return zarr.create_array(
        store=str(path),
        zarr_format=3,
        serializer=shard_codec,
        compressors=[],
        filters=[],
        **kwargs,
    )


def main() -> None:
    if zarr.__version__ != "3.4.0":
        raise RuntimeError(f"expected zarr-python 3.4.0, got {zarr.__version__}")

    end = new_array(
        "v3_shard_end_gzip_u16",
        shape=(5, 7),
        chunks=(4, 4),
        dtype="uint16",
        fill_value=7,
        shard_codec=ShardingCodec(
            chunk_shape=(2, 2),
            codecs=[BytesCodec(endian="little"), GzipCodec(level=1)],
            index_codecs=[BytesCodec(endian="little"), Crc32cCodec()],
            index_location="end",
        ),
    )
    end[0:3, 1:6] = (np.arange(15, dtype=np.uint16).reshape(3, 5) + 100)
    np.testing.assert_array_equal(end[4, :], np.full(7, 7, dtype=np.uint16))

    start = new_array(
        "v3_shard_start_u8",
        shape=(9,),
        chunks=(8,),
        dtype="uint8",
        fill_value=5,
        shard_codec=ShardingCodec(
            chunk_shape=(2,),
            codecs=[BytesCodec()],
            index_codecs=[BytesCodec(), Crc32cCodec()],
            index_location="start",
        ),
    )
    start[1] = 11
    start[6] = 22
    start[8] = 33

    big_index = new_array(
        "v3_shard_big_index_f32",
        shape=(10,),
        chunks=(8,),
        dtype="float32",
        fill_value=1.5,
        shard_codec=ShardingCodec(
            chunk_shape=(2,),
            codecs=[BytesCodec(endian="big")],
            index_codecs=[BytesCodec(endian="big")],
            index_location="end",
        ),
    )
    big_index[2:6] = np.array([2.25, 3.5, -1.0, 9.0], dtype=np.float32)

    blosc = new_array(
        "v3_shard_blosc_u16",
        shape=(32,),
        chunks=(16,),
        dtype="uint16",
        fill_value=0,
        shard_codec=ShardingCodec(
            chunk_shape=(8,),
            codecs=[
                BytesCodec(endian="little"),
                BloscCodec(typesize=2, cname="lz4", clevel=5, shuffle="shuffle"),
            ],
            index_codecs=[BytesCodec(), Crc32cCodec()],
            index_location="end",
        ),
    )
    blosc[3:23] = np.arange(20, dtype=np.uint16) + 200

    for name in (
        "v3_shard_end_gzip_u16",
        "v3_shard_start_u8",
        "v3_shard_big_index_f32",
        "v3_shard_blosc_u16",
    ):
        path = ROOT / f"{name}.zarr"
        array = zarr.open_array(str(path), mode="r")
        print(f"{name}: shape={array.shape}, dtype={array.dtype}")


if __name__ == "__main__":
    main()
