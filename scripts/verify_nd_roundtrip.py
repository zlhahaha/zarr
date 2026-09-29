"""Verify all eight MoonBit-written N-D arrays with an independent Python oracle."""
from pathlib import Path
import argparse
import json
from generate_nd_fixtures import PROJECT, expected, np, zarr


def main(root):
    if zarr.__version__ != "3.4.0" or np.__version__ != "2.5.3":
        raise RuntimeError("install zarr==3.4.0 numpy==2.5.3")
    cases = [
        ("nd3_v2_raw_u16", 3, 2, "C", "raw"),
        ("nd3_v2_f_gzip_be_u16", 3, 2, "F", "gzip"),
        ("nd3_v3_zstd_u16", 3, 3, "C", "zstd"),
        ("nd3_v3_gzip_be_u16", 3, 3, "C", "gzip"),
        ("nd4_v2_gzip_f32", 4, 2, "C", "gzip"),
        ("nd4_v2_f_zlib_be_f32", 4, 2, "F", "zlib"),
        ("nd4_v3_raw_be_f32", 4, 3, "C", "raw"),
        ("nd4_v3_zstd_f32", 4, 3, "C", "zstd"),
    ]
    for name, rank, fmt, order, compression in cases:
        path = root / f"{name}.zarr"
        array = zarr.open_array(str(path), mode="r")
        values, region, corner = expected(rank)
        assert array.shape == values.shape
        assert array.chunks == ((2, 3, 4) if rank == 3 else (2, 2, 3, 3))
        assert array.dtype.kind == values.dtype.kind and array.dtype.itemsize == values.dtype.itemsize
        np.testing.assert_array_equal(array[:], values)
        np.testing.assert_array_equal(array[region], values[region])
        assert array[corner] == values[corner]
        metadata = json.loads((path / (".zarray" if fmt == 2 else "zarr.json")).read_text())
        assert metadata["zarr_format"] == fmt
        if fmt == 2:
            assert metadata["order"] == order
            assert (metadata["compressor"] or {}).get("id", "raw") == compression
            assert metadata["dtype"] == ((">" if "_be_" in name else "<") + ("u2" if rank == 3 else "f4"))
        else:
            assert metadata["codecs"][0]["configuration"]["endian"] == ("big" if "_be_" in name else "little")
            assert ([c["name"] for c in metadata["codecs"]][1:] or ["raw"]) == [compression]
        print(f"verified {name}: all {values.size} values, slices, edge rewrite, metadata")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=PROJECT / "integration/.roundtrip")
    main(parser.parse_args().root)
