"""Verify MoonBit-written v2/v3 arrays with zarr-python 3.4.0."""

from pathlib import Path
import sys

PROJECT = Path(__file__).resolve().parents[1]
DEPS = PROJECT / ".interop-deps"
if DEPS.exists():
    sys.path.insert(0, str(DEPS))

import numpy as np
import zarr


def check(name: str, expected: np.ndarray) -> None:
    path = PROJECT / "integration" / ".roundtrip" / f"{name}.zarr"
    array = zarr.open_array(store=str(path), mode="r")
    actual = array[:]
    np.testing.assert_array_equal(actual, expected)
    print(f"{name}: {actual.dtype}, shape={actual.shape}")


def check_group(name: str, title: str) -> None:
    path = PROJECT / "integration" / ".roundtrip" / f"{name}.zarr"
    root = zarr.open_group(store=str(path), mode="r")
    assert root["science"].attrs["title"] == title
    np.testing.assert_array_equal(
        root["science/image"][:], np.array([5, 5, 9], dtype=np.uint8)
    )
    print(f"{name}: nested group and array")


def main() -> None:
    if zarr.__version__ != "3.4.0":
        raise RuntimeError(f"expected zarr-python 3.4.0, got {zarr.__version__}")
    image = np.full((3, 4), 5, dtype=np.uint8)
    image[1, 2] = 7
    image[2, 3] = 9
    check("v2_u8", image)
    check("v3_u8", image)
    check("v2_f64_be", np.array([1.5, 1.5, 42.25], dtype=np.float64))
    check("v3_f32_le", np.array([1.5, 1.5, 42.25], dtype=np.float32))
    check("v3_i32_be", np.array([-1, -1, -200], dtype=np.int32))
    check("v2_gzip_u8", np.array([5, 5, 9], dtype=np.uint8))
    check("v2_zlib_f64", np.array([1.5, 1.5, 42.25], dtype=np.float64))
    check("v3_gzip_i32", np.array([-1, -1, -200], dtype=np.int32))
    check("v2_zstd_u8", np.array([5, 5, 9], dtype=np.uint8))
    check("v3_zstd_f32", np.array([1.5, 1.5, 42.25], dtype=np.float32))
    image = np.full((3, 4), 5, dtype=np.uint8)
    image[1:3, 1:4] = np.array([[1, 2, 3], [4, 5, 6]], dtype=np.uint8)
    check("v3_zstd_image", image)
    check("v2_u16_be", np.array([60000, 60000, 65530], dtype=np.uint16))
    check("v3_u16_le_zstd", np.array([60000, 60000, 65530], dtype=np.uint16))
    check("v2_i16_be", np.array([-1234, -1234, -32768], dtype=np.int16))
    check("v3_i16_le_zstd", np.array([-1234, -1234, 32767], dtype=np.int16))
    check("v2_u32_be", np.array([4000000000, 4000000000, 4294967295], dtype=np.uint32))
    check("v3_u32_le_zstd", np.array([4000000000, 4000000000, 4294967294], dtype=np.uint32))
    check_group("v2_grouped_u8", "v2")
    check_group("v3_grouped_u8", "v3")
    mask = np.ones((3, 4), dtype=np.bool_)
    mask[1:3, 1:4] = np.array(
        [[False, True, False], [True, False, True]], dtype=np.bool_
    )
    check("v2_bool", mask)
    check("v3_bool_zstd", mask)
    check("v2_f64_nan", np.array([np.nan, np.nan, 42.25], dtype=np.float64))
    check("v3_f32_neg_inf", np.array([-np.inf, -np.inf, 1.25], dtype=np.float32))
    check("v2_i64_be", np.array([-9223372036854775807, -9223372036854775807, 9223372036854775807], dtype=np.int64))
    check("v3_u64_le_zstd", np.array([18446744073709551615, 18446744073709551615, 18446744073709551614], dtype=np.uint64))
    check("v2_i8", np.array([-5, -128, 127], dtype=np.int8))
    check("v3_i8_zstd", np.array([-5, -128, 127], dtype=np.int8))


if __name__ == "__main__":
    main()
