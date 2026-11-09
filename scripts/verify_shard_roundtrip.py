"""Independent Python verification and partial updates of MoonBit shards."""
import argparse
import json
from pathlib import Path
import numpy as np
import zarr


def verify(root):
    assert zarr.__version__ == "3.4.0" and np.__version__ == "2.5.3"
    for case in range(8):
        path = root / f"u8-{case}.zarr"
        array = zarr.open_array(str(path), mode="r")
        np.testing.assert_array_equal(array[:], np.array([11, 12, 13, 14, 5, 5, 5, 5, 9], dtype=np.uint8))
        raw = json.loads((path / "zarr.json").read_text(encoding="utf-8"))
        config = raw["codecs"][0]["configuration"]
        assert config["index_location"] == ("start" if case & 1 else "end")
        assert config["index_codecs"][0]["configuration"]["endian"] == ("big" if case & 2 else "little")
        assert len(config["index_codecs"]) == (2 if case & 4 else 1)
        assert array.chunks == (2,) and array.shards == (4,)
        assert not (path / "c/1").exists(), "whole absent shard must preserve missing fill"
    array = zarr.open_array(str(root / "u16.zarr"), mode="r")
    expected = np.arange(5, dtype=np.uint16)[:, None] * 100 + np.arange(7, dtype=np.uint16)[None, :]
    np.testing.assert_array_equal(array[:], expected)
    assert array.chunks == (2, 2) and array.shards == (4, 4)
    array = zarr.open_array(str(root / "f32.zarr"), mode="r")
    expected = np.arange(105, dtype=np.float32).reshape(3, 5, 7) / 4 - 10
    np.testing.assert_array_equal(array[:], expected)
    assert array.chunks == (2, 2, 2) and array.shards == (2, 4, 4)
    # Exercise the opposite direction with foreign partial-shard updates.
    zarr.open_array(str(root / "u8-0.zarr"), mode="r+")[1] = 77
    zarr.open_array(str(root / "u16.zarr"), mode="r+")[4, 6] = 65535
    zarr.open_array(str(root / "f32.zarr"), mode="r+")[1, 3, 5] = -2.25
    print("Python verified all 10 MoonBit shard stores and performed three partial updates")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    verify(parser.parse_args().root)
