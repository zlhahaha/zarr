"""Run the independent volume application against source or a registry release.

The default installs the example's pinned registry dependency. --source uses an
explicit temporary workspace to test the checkout before publishing it.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
from functools import partial
import hashlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import threading

import numpy as np
import numcodecs
import zarr

PROJECT = Path(__file__).resolve().parents[1]
APP = PROJECT / "examples/volume_pipeline"


@contextmanager
def source_workspace(enabled):
    manifest = PROJECT / "moon.work"
    if not enabled:
        yield
        return
    # Workspace discovery starts at a module, so place this at the module root.
    # Exclusive creation protects any developer-owned workspace manifest.
    with manifest.open("x", encoding="utf-8") as stream:
        stream.write('members = [".", "./examples/volume_pipeline"]\n')
    try:
        yield
    finally:
        manifest.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", action="store_true")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--s3-endpoint", help="optional isolated MinIO endpoint; requires explicit environment credentials")
    parser.add_argument("--s3-bucket")
    args = parser.parse_args()
    assert zarr.__version__ == "3.4.0" and np.__version__ == "2.5.3"
    version = re.search(r'"zlhahaha/zarr@([^"\s]+)"', (APP / "moon.mod").read_text())[1]
    scratch = PROJECT / "_build/volume-pipeline"
    scratch.mkdir(parents=True, exist_ok=True)
    records = []
    with source_workspace(args.source), tempfile.TemporaryDirectory(dir=scratch) as directory:
        root = Path(directory).resolve()
        cwd = PROJECT if args.source else APP

        def command(parts, success=True):
            result = subprocess.run(["moon", *parts], cwd=cwd, capture_output=True,
                                    text=True, encoding="utf-8", errors="replace", timeout=600)
            if (result.returncode == 0) != success:
                raise RuntimeError(f"unexpected application status: {parts[:3]}\n{result.stdout}\n{result.stderr}")
            return result.stdout

        command(["check", "--target", "native", "--deny-warn"])
        command(["build", "--target", "native"])
        if not args.source:
            installed = APP / ".mooncakes/zlhahaha/zarr"
            assert installed.resolve() != PROJECT.resolve()
            assert f'version = "{version}"' in (installed / "moon.mod").read_text()
        # Each mode reads a non-aligned crop crossing both input chunks and
        # output shards. Values deliberately exercise all 256 intensity bins.
        values = (np.arange(11 * 37 * 39, dtype=np.uint32) * 17 % 256).astype(np.uint8).reshape(11, 37, 39)
        origin, extent = [1, 2, 3], [9, 34, 35]
        roi = values[1:10, 2:36, 3:38]
        expected = roi.astype(np.float32) / np.float32(255)
        for name, fmt, sharded in [("v2", 2, False), ("v3", 3, False), ("sharded", 3, True)]:
            options = ({"compressors": [numcodecs.GZip(level=1)]} if fmt == 2
                       else {"compressors": [zarr.codecs.GzipCodec(level=1)]})
            if sharded:
                options["shards"] = (6, 26, 20)
            array = zarr.create_array(str(root / name), shape=values.shape, chunks=(3, 13, 10),
                                      dtype="uint8", zarr_format=fmt, **options)
            array[:] = values

        class Handler(SimpleHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def log_message(self, *_):
                pass

            def do_GET(self):
                path = Path(self.translate_path(self.path))
                if not path.is_file():
                    records.append((self.path, 404, False))
                    self.send_error(404)
                    return
                data = path.read_bytes()
                etag = '"' + hashlib.sha256(data).hexdigest() + '"'
                requested = self.headers.get("Range")
                if self.headers.get("If-Match", etag) != etag:
                    self.send_response(412)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                status, start, end = 200, 0, len(data) - 1
                if requested:
                    assert requested.startswith("bytes=")
                    left, right = requested[6:].split("-", 1)
                    start, end = ((int(left), int(right) if right else len(data) - 1)
                                  if left else (max(0, len(data) - int(right)), len(data) - 1))
                    assert 0 <= start <= end < len(data)
                    status = 206
                body = data[start:end + 1]
                records.append((self.path, status, bool(requested)))
                self.send_response(status)
                self.send_header("ETag", etag)
                if requested:
                    self.send_header("Content-Range", f"bytes {start}-{end}/{len(data)}")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        server = ThreadingHTTPServer(("127.0.0.1", 0), partial(Handler, directory=str(root)))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        modes = []
        try:
            url = f"http://127.0.0.1:{server.server_port}"
            cases = [(str(root / name), "", "local-" + name) for name in ("v2", "v3", "sharded")]
            cases += [(url, name, "http-" + name) for name in ("v2", "v3", "sharded")]
            if args.s3_endpoint:
                import boto3
                from botocore.config import Config
                assert args.s3_bucket and os.environ["ZARR_ACCESS_KEY"] and os.environ["ZARR_SECRET_KEY"]
                client = boto3.client("s3", endpoint_url=args.s3_endpoint, region_name="us-east-1",
                                      aws_access_key_id=os.environ["ZARR_ACCESS_KEY"],
                                      aws_secret_access_key=os.environ["ZARR_SECRET_KEY"],
                                      config=Config(signature_version="s3v4", proxies={}, s3={"addressing_style": "path"}))
                for path in (root / "sharded").rglob("*"):
                    if path.is_file():
                        client.put_object(Bucket=args.s3_bucket, Key="pipeline/" + path.relative_to(root / "sharded").as_posix(), Body=path.read_bytes())
                cases.append((f"s3://{args.s3_bucket}/pipeline", "", "s3-sharded"))
            for source, array_path, label in cases:
                records.clear()
                output = root / ("output-" + label)
                invocation = ["run", "--target", "native", str(APP), source, array_path, str(output),
                              *map(str, origin), *map(str, extent)]
                stdout = command(invocation)
                summary = json.loads(stdout.strip().splitlines()[-1])
                assert summary["voxels"] == roi.size and summary["input_checksum"] == int(roi.sum())
                assert summary["histogram"] == np.bincount(roi.ravel(), minlength=256).tolist()
                assert summary["shards"] == 8
                result = zarr.open_array(str(output), mode="r")
                np.testing.assert_array_equal(result[:], expected)
                assert result.chunks == (2, 16, 16) and result.shards == (8, 32, 32)
                assert result.dtype == np.dtype("float32")
                attrs = result.attrs["processing"]
                assert attrs["roi_origin"] == origin and attrs["roi_shape"] == extent
                if label.startswith("http-"):
                    metadata = [r for r in records if r[0].endswith(("/.zarray", "/.zgroup", "/zarr.json"))]
                    assert len(metadata) == 3, "scan must pin metadata across all eight tiles"
                    if label == "http-sharded":
                        assert any(r[1] == 206 and r[2] for r in records), "Range reads not exercised"
                before = {p.relative_to(output): p.read_bytes() for p in output.rglob("*") if p.is_file()}
                command(invocation, success=False)
                assert before == {p.relative_to(output): p.read_bytes() for p in output.rglob("*") if p.is_file()}
                modes.append(label)
                print(f"volume pipeline verified {label}: {roi.size} float32 values, eight shards, histogram, no overwrite")
            bad = root / "invalid-output"
            command(["run", "--target", "native", str(APP), str(root / "v3"), "", str(bad),
                     "100", "0", "0", "1", "1", "1"], success=False)
            assert not bad.exists()
            wrong = zarr.create_array(str(root / "wrong-dtype"), shape=(2, 2, 2), chunks=(2, 2, 2), dtype="uint16")
            wrong[:] = 300
            for source, path in [(str(root / "wrong-dtype"), ""), (url, "wrong-dtype")]:
                command(["run", "--target", "native", str(APP), source, path, str(bad),
                         "0", "0", "0", "1", "1", "1"], success=False)
                assert not bad.exists()
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)
        report = {"dependency": f"zlhahaha/zarr@{version}",
                  "resolution": "explicit source workspace" if args.source else "registry; no local override",
                  "modes": modes, "values_per_mode": int(roi.size), "output_shards_per_mode": 8,
                  "every_value_verified": True, "metadata_requests_per_http_scan": 3,
                  "overwrite_rejected": True, "invalid_roi_creates_no_output": True,
                  "wrong_dtype_creates_no_output": True,
                  "scope": "independent module in this repository; not an external adopter or clinical pipeline"}
        if args.output:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
