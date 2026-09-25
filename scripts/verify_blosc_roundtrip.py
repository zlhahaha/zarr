"""Independently open MoonBit-written Blosc LZ4 stores with zarr-python."""

from pathlib import Path
import sys

PROJECT = Path(__file__).resolve().parents[1]
DEPS = PROJECT / ".interop-deps"
if DEPS.exists():
    sys.path.insert(0, str(DEPS))

import numpy as np
import zarr


def main() -> None:
    if zarr.__version__ != "3.4.0":
        raise RuntimeError(f"expected zarr-python 3.4.0, got {zarr.__version__}")
    base = PROJECT / "integration" / ".roundtrip"
    for name in (
        "v2_blosc_lz4_shuffle_u16",
        "v3_blosc_lz4_bitshuffle_u16",
        "v3_blosc_lz4_noshuffle_u16",
    ):
        array = zarr.open_array(str(base / f"{name}.zarr"), mode="r")
        np.testing.assert_array_equal(
            array[:], np.arange(4096, dtype=np.uint16) % 64
        )
        if name.startswith("v2_"):
            frame = (base / f"{name}.zarr" / "0").read_bytes()
        else:
            frame = (base / f"{name}.zarr" / "c" / "0").read_bytes()
        assert frame[0] == 2 and frame[1] == 1
        assert not frame[2] & 2, f"expected compressed LZ4 frame: {name}"
        print(f"{name}: {array.dtype}, shape={array.shape}")
    array = zarr.open_array(str(base / "v2_blosc_lz4_memcpy_u8.zarr"), mode="r")
    np.testing.assert_array_equal(array[:], np.frombuffer(b"abcde", dtype=np.uint8))
    frame = (base / "v2_blosc_lz4_memcpy_u8.zarr" / "0").read_bytes()
    assert frame[2] & 2, "expected Blosc memcpy fallback"
    print("v2_blosc_lz4_memcpy_u8: uint8, shape=(5,)")


if __name__ == "__main__":
    main()
