"""Export hash-pinned public CT patches with the registry Zarr package and verify them in NumPy."""

import argparse
from collections import Counter
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from math import prod
from pathlib import Path
import re
import subprocess
import threading

import numpy as np
import zarr

from benchmark_real_scan import PROJECT, prepare


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download", action="store_true", help="fetch missing hash-pinned source objects")
    parser.add_argument("--batch", action="store_true", help="prepare four CT patches as an NCDHW float32 batch")
    parser.add_argument("--output-dir", type=Path, default=PROJECT / "_build/zarr-npy-roi")
    args = parser.parse_args()

    app = PROJECT / "examples/zarr_npy_roi"
    for directory in (app, *app.parents):
        if any((directory / name).exists() for name in ("moon.work", "moon.work.json")):
            raise RuntimeError("Run this registry consumer outside a MoonBit workspace override")

    source = PROJECT / "_build/real-scan-data"
    _, objects = prepare(source, args.download)
    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=False)
    output = output_dir / ("bonsai-patches.npy" if args.batch else "bonsai-roi.npy")
    origins = [[56, 56, 56]]
    if args.batch:
        origins.extend([[0, 0, 0], [8, 8, 8], [112, 112, 112]])
    requests = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            body = objects.get(self.path)
            code = 200 if body is not None else 404
            body = body or b""
            requests.append((self.path, code, len(body)))
            self.send_response(code)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_):
            pass

    with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            url = f"http://127.0.0.1:{server.server_port}"
            command = ["moon", "run", "--target", "native", "--release", ".", "--", url, str(output)]
            if args.batch:
                command.append("--batch")
            result = subprocess.run(command, cwd=app, check=True, timeout=300, stdout=subprocess.PIPE, text=True)
            assert json.loads(result.stdout) == origins
        finally:
            server.shutdown()
            thread.join()

    pin = re.search(r'"zlhahaha/zarr@([^"\s]+)"', (app / "moon.mod").read_text(encoding="utf-8"))
    if pin is None:
        raise RuntimeError("the application must pin a registry version")
    version = pin.group(1)
    dependency = app / ".mooncakes/zlhahaha/zarr"
    assert dependency.resolve() != PROJECT and f'version = "{version}"' in (dependency / "moon.mod").read_text(encoding="utf-8")
    payloads = {f"/{i}/{j}/{k}" for i in range(2) for j in range(2) for k in range(2)}
    expected_gets = Counter(payloads | {"/.zarray", "/.zgroup", "/zarr.json"})
    assert Counter(path for path, _, _ in requests) == expected_gets, requests
    assert {path for path, code, _ in requests if code == 200} == payloads | {"/.zarray"}

    actual = np.load(output, allow_pickle=False)
    array = zarr.open_array(str(source), mode="r")
    expected_patches = [array[tuple(slice(axis, axis + 16) for axis in origin)] for origin in origins]
    expected = np.stack(expected_patches) if args.batch else expected_patches[0]
    assert actual.dtype == np.uint8 and actual.shape == expected.shape
    np.testing.assert_array_equal(actual, expected)
    report = {
        "status": "verified",
        "dependency": f"zlhahaha/zarr@{version} (registry)",
        "origins": origins,
        "shape": list(actual.shape),
        "dtype": str(actual.dtype),
        "values_verified": int(actual.size),
        "patch_chunk_intersections": sum(
            prod((axis + 15) // chunk - axis // chunk + 1 for axis, chunk in zip(origin, array.chunks))
            for origin in origins
        ),
        "payload_gets": len(payloads),
        "response_body_bytes": sum(size for _, _, size in requests),
        "requests": [{"path": path, "status": code, "bytes": size} for path, code, size in requests],
        "output": output.name,
        "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
    }
    if args.batch:
        model_input = actual.astype(np.float32)[:, None] / np.float32(255)
        prepared = output_dir / "model-input.npy"
        np.save(prepared, model_input, allow_pickle=False)
        saved = np.load(prepared, allow_pickle=False)
        assert saved.dtype == np.float32 and saved.shape == (len(origins), 1, 16, 16, 16)
        np.testing.assert_array_equal(saved[:, 0], expected.astype(np.float32) / np.float32(255))
        report["preprocessed"] = {
            "file": prepared.name,
            "layout": "NCDHW",
            "shape": list(saved.shape),
            "dtype": str(saved.dtype),
            "values_verified": int(saved.size),
            "sha256": hashlib.sha256(prepared.read_bytes()).hexdigest(),
        }
    (output_dir / "verification.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Verified all {actual.size} values from {len(payloads)} source chunks: {output}")


if __name__ == "__main__":
    main()
