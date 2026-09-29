"""Generate eight independent 3D/4D fixtures; never overwrite a store.

Pinned oracle: zarr-python 3.4.0, NumPy 2.5.3. Defaults to committed fixture
directory; --output allows a fresh directory for regeneration/checking.
"""
from pathlib import Path
import argparse
import sys

PROJECT = Path(__file__).resolve().parents[1]
DEPS = PROJECT / ".interop-deps"
if DEPS.exists():
    sys.path.insert(0, str(DEPS))

import numpy as np
import zarr
from numcodecs import GZip, Zlib
from zarr.codecs import BytesCodec, Crc32cCodec, GzipCodec, ZstdCodec, ShardingCodec


def expected(rank):
    """Coordinate-weighted values reveal axis, endian and memory-order errors."""
    if rank == 3:
        shape, region, fill = (5, 7, 9), (slice(1, 5), slice(1, 4), slice(1, 9)), 60000
        x, y, z = np.indices(shape)
        values = (1000 * x + 100 * y + z + 1).astype(np.uint16)
    else:
        shape, region, fill = (3, 5, 7, 4), (slice(1, 3), slice(1, 3), slice(1, 7), slice(1, 4)), -1.5
        t, y, z, c = np.indices(shape)
        values = (100 * t + 10 * y + z + c / 4 - 50).astype(np.float32)
    result = np.full(shape, fill, dtype=values.dtype)
    result[region] = values[region]
    corner = tuple(s.stop - 1 for s in region)
    result[corner] += 7
    return result, region, corner


def main(root):
    if zarr.__version__ != "3.4.0" or np.__version__ != "2.5.3":
        raise RuntimeError("install zarr==3.4.0 numpy==2.5.3")
    cases = [
        ("nd3_v2_raw_u16", 3, 2, "C", "little", "raw", None),
        ("nd3_v2_f_gzip_be_u16", 3, 2, "F", "big", "gzip", None),
        ("nd3_v3_zstd_u16", 3, 3, "C", "little", "zstd", None),
        ("nd3_v3_shard_gzip_be_u16", 3, 3, "C", "big", "gzip", "end"),
        ("nd4_v2_gzip_f32", 4, 2, "C", "little", "gzip", None),
        ("nd4_v2_f_zlib_be_f32", 4, 2, "F", "big", "zlib", None),
        ("nd4_v3_raw_be_f32", 4, 3, "C", "big", "raw", None),
        ("nd4_v3_shard_zstd_f32", 4, 3, "C", "little", "zstd", "start"),
    ]
    for name, rank, fmt, order, endian, compression, index in cases:
        path = root / f"{name}.zarr"
        if path.exists():
            raise FileExistsError(f"refusing to overwrite {path}")
        values, region, corner = expected(rank)
        chunks = (2, 3, 4) if rank == 3 else (2, 2, 3, 3)
        kwargs = dict(store=str(path), shape=values.shape, chunks=chunks,
                      dtype=values.dtype, fill_value=60000 if rank == 3 else -1.5,
                      zarr_format=fmt, overwrite=False)
        if fmt == 2:
            kwargs.update(dtype=np.dtype((">" if endian == "big" else "<") + ("u2" if rank == 3 else "f4")),
                          order=order, compressor={"raw": None, "gzip": GZip(1), "zlib": Zlib(1)}[compression], filters=None)
            array = zarr.create(**kwargs)
        else:
            codecs = [BytesCodec(endian=endian)]
            if compression == "gzip": codecs.append(GzipCodec(level=1))
            if compression == "zstd": codecs.append(ZstdCodec(level=3))
            if index:
                kwargs.update(chunks=tuple(n * 2 for n in chunks),
                              serializer=ShardingCodec(chunk_shape=chunks, codecs=codecs,
                                  index_codecs=[BytesCodec(), Crc32cCodec()], index_location=index),
                              compressors=[], filters=[])
            else:
                kwargs.update(serializer=codecs[0], compressors=codecs[1:], filters=[])
            array = zarr.create_array(**kwargs)
        initial = values.copy()
        initial[corner] -= 7
        array[region] = initial[region]
        array[corner] = values[corner]  # rewrite existing edge chunk
        reopened = zarr.open_array(str(path), mode="r")
        np.testing.assert_array_equal(reopened[:], values)
        print(f"{name}: {values.shape}, {values.dtype}, {order}, {endian}, {compression}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=PROJECT / "integration/fixtures/zarr-python")
    main(parser.parse_args().output)
