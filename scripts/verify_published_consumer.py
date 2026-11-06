"""Check an independent registry-only 0.7.0 consumer with the active toolchain."""
import argparse
import json
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
        manifest = (CONSUMER / ".mooncakes" / "zlhahaha" / "zarr" / "moon.mod").read_text(encoding="utf-8")
        assert 'version = "0.7.0"' in manifest, "consumer did not install registry 0.7.0"
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
        report = {"package": "zlhahaha/zarr@0.7.0", "source": "registry dependency; no local path override",
                  "toolchain": subprocess.check_output(["moon", "version", "--all"], text=True).strip(),
                  "zarr_python": zarr.__version__, "numpy": np.__version__,
                  "native_check_build_run": True, "python_v2_v3_values": True}
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
