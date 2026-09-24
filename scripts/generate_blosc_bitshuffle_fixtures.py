"""Generate independent v2/v3 Blosc bitshuffle fixtures with zarr-python 3.4.0."""

import sys

from generate_blosc_fixtures import (
    BloscCodec,
    BytesCodec,
    create,
    np,
    numcodecs,
    zarr,
)


def create_float_fixture() -> None:
    f32 = create(
        "v3_blosc_bitshuffle_f32",
        zarr_format=3,
        shape=(1024,),
        chunks=(1024,),
        dtype=np.dtype("f4"),
        fill_value=1.5,
        serializer=BytesCodec(endian="little"),
        compressors=[
            BloscCodec(typesize=4, cname="lz4", clevel=5, shuffle="bitshuffle")
        ],
        filters=[],
    )
    f32[:] = np.full(1024, 1.5, dtype=np.float32)
    f32[1023] = np.float32(42.25)


def main() -> None:
    if zarr.__version__ != "3.4.0":
        raise RuntimeError(f"expected zarr-python 3.4.0, got {zarr.__version__}")
    values = (np.arange(4096, dtype=np.uint16) % 64).astype("<u2")
    v2 = create(
        "v2_blosc_bitshuffle_u16",
        zarr_format=2,
        shape=(4096,),
        chunks=(4096,),
        dtype=np.dtype("<u2"),
        fill_value=0,
        compressors=numcodecs.Blosc(cname="lz4", clevel=5, shuffle=2),
        filters=None,
    )
    v2[:] = values
    v3 = create(
        "v3_blosc_bitshuffle_u16",
        zarr_format=3,
        shape=(4096,),
        chunks=(4096,),
        dtype=np.dtype("u2"),
        fill_value=0,
        serializer=BytesCodec(endian="little"),
        compressors=[
            BloscCodec(typesize=2, cname="lz4", clevel=5, shuffle="bitshuffle")
        ],
        filters=[],
    )
    v3[:] = values
    create_float_fixture()
    many = create(
        "v2_blosc_bitshuffle_multiblock_u16",
        zarr_format=2,
        shape=(8200,),
        chunks=(8200,),
        dtype=np.dtype("<u2"),
        fill_value=0,
        compressors=numcodecs.Blosc(
            cname="lz4", clevel=5, shuffle=2, blocksize=1024
        ),
        filters=None,
    )
    many[:] = (np.arange(8200, dtype=np.uint16) % 64).astype("<u2")
    print("v2_blosc_bitshuffle_u16 v3_blosc_bitshuffle_u16 v3_blosc_bitshuffle_f32 v2_blosc_bitshuffle_multiblock_u16")


if __name__ == "__main__":
    if sys.argv[1:] == ["--f32-only"]:
        create_float_fixture()
    elif not sys.argv[1:]:
        main()
    else:
        raise SystemExit("usage: generate_blosc_bitshuffle_fixtures.py [--f32-only]")
