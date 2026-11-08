"""Hash-pinned real OME-Zarr: independently verified tiled histogram and RSS.

Download only metadata and eight chunks on explicit --download. Measurements
replay those exact encoded objects over loopback HTTP, excluding WAN variance.
No upstream dataset bytes are committed or redistributed with this package.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import platform
import statistics
import subprocess
import threading
import time
import urllib.request

import numpy as np
import zarr

PROJECT = Path(__file__).resolve().parents[1]
MANIFEST = Path(__file__).with_name("real_scan_manifest.json")


def prepare(root, download):
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    objects = {}
    for entry in manifest["objects"]:
        key = entry["key"]
        target = root / key
        if not target.exists():
            if not download:
                raise FileNotFoundError(f"missing {key}; explicitly use --download")
            for attempt in range(3):
                try:
                    with urllib.request.urlopen(manifest["base_url"] + "/" + key, timeout=45) as response:
                        data = response.read(entry["bytes"] + 1)
                    break
                except OSError:
                    if attempt == 2:
                        raise
                    time.sleep(1)
            # Never accept an upstream change or an incomplete download.
            if len(data) != entry["bytes"] or hashlib.sha256(data).hexdigest() != entry["sha256"]:
                raise ValueError(f"upstream object differs from pinned manifest: {key}")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        data = target.read_bytes()
        if len(data) != entry["bytes"] or hashlib.sha256(data).hexdigest() != entry["sha256"]:
            raise ValueError(f"local object differs from pinned manifest: {key}")
        objects["/" + key] = data
    return manifest, objects


def run(args):
    if zarr.__version__ != "3.4.0" or np.__version__ != "2.5.3":
        raise RuntimeError("install zarr==3.4.0 numpy==2.5.3")
    if args.output.exists():
        raise FileExistsError(f"refusing to overwrite report: {args.output}")
    manifest, objects = prepare(args.work_dir.resolve(), args.download)
    array = zarr.open_array(str(args.work_dir.resolve()), mode="r")
    assert array.shape == (256, 256, 256) and array.chunks == (64, 64, 64)
    values = np.asarray(array[:128, :128, :128])
    assert values.dtype == np.uint8 and int(values.sum()) == 24039966
    histogram = np.bincount(values.ravel(), minlength=256)
    weighted = int(np.dot(values.ravel().astype(np.int64), np.arange(1, values.size + 1, dtype=np.int64)))
    subprocess.run(["moon", "run", "--target", "native", "--release", "--build-only", "cmd/scan_benchmark"], cwd=PROJECT, check=True)
    binary = PROJECT / "_build/native/release/build/cmd/scan_benchmark/scan_benchmark.exe"
    records = []

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def do_GET(self):
            body = objects.get(self.path)
            status = 200 if body is not None else 404
            body = body or b""
            records.append({"key": self.path, "status": status, "bytes": len(body)})
            self.send_response(status)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *_args):
            pass

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    cases = []
    try:
        for side, passes in [(32, 1), (64, 1), (64, 2 if args.quick else 8)]:
            samples = []
            for _ in range(args.trials):
                records.clear()
                result = subprocess.run([str(binary), f"http://127.0.0.1:{server.server_port}", str(side), str(passes)], cwd=PROJECT,
                                        capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=180)
                if result.returncode:
                    raise RuntimeError(result.stdout + result.stderr)
                sample = json.loads(result.stdout)
                assert sample.pop("histogram") == (histogram * passes).tolist()
                assert sample["checksum"] == int(values.sum()) * passes
                assert sample["weighted_checksum"] == weighted * passes
                assert sample["voxels"] == values.size * passes
                assert sample["tiles"] == (128 // side) ** 3 * passes
                payloads = [r for r in records if r["status"] == 200 and r["key"] != "/.zarray"]
                assert len(payloads) == sample["tiles"], "cache is disabled; one object per aligned/subchunk tile"
                sample.update(requests=len(records), payload_requests=len(payloads), transferred_bytes=sum(r["bytes"] for r in records))
                samples.append(sample)
            cases.append({"tile_side": side, "passes": passes, "samples": samples,
                          "median_ms": statistics.median(s["elapsed_ns"] for s in samples) / 1e6,
                          "max_peak_rss_bytes": max(s["peak_rss_bytes"] for s in samples)})
            print(f"real scan side={side}, passes={passes}: {cases[-1]['median_ms']:.2f} ms, {cases[-1]['max_peak_rss_bytes']/1048576:.2f} MiB peak", flush=True)
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
    source = hashlib.sha256()
    for name in sorted(subprocess.check_output(["git", "ls-files", "--cached", "--others", "--exclude-standard"], cwd=PROJECT, text=True).splitlines()):
        if name.endswith((".mbt", ".c", "moon.pkg", "moon.mod")) and (PROJECT / name).is_file():
            source.update(name.encode())
            source.update((PROJECT / name).read_bytes())
    report = {"timestamp": datetime.now(timezone.utc).isoformat(), "platform": platform.platform(),
              "commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=PROJECT, text=True).strip(),
              "source_sha256": source.hexdigest(),
              "toolchain": subprocess.check_output(["moon", "version", "--all"], text=True).strip(),
              "manifest": manifest, "python": {"zarr": zarr.__version__, "numpy": np.__version__},
              "oracle": {"checksum": int(values.sum()), "weighted_checksum": weighted, "histogram": histogram.tolist()},
              "scope": "fresh-process release native; exact real encoded chunks replayed over loopback HTTP; cache disabled; not WAN/cloud throughput or total-memory guarantee",
              "cases": cases}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, default=PROJECT / "_build/real-scan-data")
    parser.add_argument("--output", type=Path, default=PROJECT / "_build/real-scan.json")
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--trials", type=int, default=3)
    parser.add_argument("--quick", action="store_true")
    args = parser.parse_args()
    if not 1 <= args.trials <= 10:
        parser.error("trials must be in 1..10")
    run(args)
