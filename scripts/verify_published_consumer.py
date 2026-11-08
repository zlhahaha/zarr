"""Check the independent registry-only consumer with the active toolchain."""
import argparse
import json
import re
from pathlib import Path
import subprocess
import tempfile

import numpy as np
import zarr

PROJECT = Path(__file__).resolve().parents[1]
CONSUMER = PROJECT / "scripts" / "published_consumer"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    dependency = re.search(r'"zlhahaha/zarr@([^"\s]+)"', (CONSUMER / "moon.mod").read_text(encoding="utf-8"))
    if dependency is None:
        raise RuntimeError("consumer must pin an exact registry version")
    version = dependency.group(1)
    scratch = PROJECT / "_build" / "published-consumer"
    scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=scratch) as directory:
        root = Path(directory)
        commands = [["moon", "check", "--target", "native", "--deny-warn"],
                    ["moon", "build", "--target", "native"],
                    ["moon", "run", "--target", "native", ".", str(root)]]
        for command in commands:
            result = subprocess.run(command, cwd=CONSUMER, capture_output=True, text=True,
                                    encoding="utf-8", errors="replace", timeout=180)
            if result.returncode:
                raise RuntimeError(f"consumer command failed: {command[:3]}\n{result.stdout}\n{result.stderr}")
            if command[1] == "run":
                print(result.stdout.strip())
        module_root = CONSUMER / ".mooncakes" / "zlhahaha" / "zarr"
        assert module_root.resolve() != PROJECT.resolve(), "consumer must not resolve to checkout source"
        manifest = (module_root / "moon.mod").read_text(encoding="utf-8")
        assert f'version = "{version}"' in manifest, "consumer did not install the pinned registry version"
        expected = np.full((3, 4, 5), 60000, dtype=np.uint16)
        expected[1:3, 1:3, 1:4] = np.arange(100, 112, dtype=np.uint16).reshape(2, 2, 3)
        for fmt in ("v2", "v3"):
            array = zarr.open_array(str(root / fmt), mode="r")
            np.testing.assert_array_equal(array[:], expected)
            assert array.chunks == (2, 3, 2)
            metadata_path = root / fmt / (".zarray" if fmt == "v2" else "zarr.json")
            metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
            if fmt == "v2":
                assert metadata["compressor"]["id"] == "gzip"
            else:
                assert metadata["codecs"][-1]["name"] == "zstd"
            print(f"independent Python verified registry {fmt}: all 60 values, compression and edge chunks")
        group = zarr.open_group(str(root / "groups"), mode="r")
        assert sorted(group.group_keys()) == ["a"]
        assert sorted(group.array_keys()) == ["b"]
        np.testing.assert_array_equal(group["b"][:], np.array([7], dtype=np.uint8))
        print("independent Python verified published group hierarchy")
        report = {"package": f"zlhahaha/zarr@{version}", "source": "registry dependency; no local path override",
                  "toolchain": subprocess.check_output(["moon", "version", "--all"], text=True).strip(),
                  "zarr_python": zarr.__version__, "numpy": np.__version__,
                  "native_check_build_run": True, "python_v2_v3_values": True,
                  "discovery_and_structured_errors": True, "python_group_hierarchy": True,
                  "portable_native_typed_scans": True}
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
