"""Alternating MoonBit/Python conversions of identical hash-pinned CT ROIs.

Both paths use one tile per output shard, encoded-object caching, float32 /255,
histogram/provenance, Zstd level 3, and data-synced single-key replacement.
The Python path is a small task-specific reference, not zarr-python defaults.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import platform
import statistics
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request

import numpy as np
import zarr
from zarr.core.buffer import default_buffer_prototype

from benchmark_real_scan import MANIFEST, prepare
from verify_real_volume_pipeline import build_app, verify_output, write_json, command
from verify_volume_pipeline import APP, PROJECT


def atomic_put(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(prefix=".zarr-tmp-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


class SyncedStore(zarr.storage.LocalStore):
    async def set(self, key, value):
        if self.read_only:
            raise PermissionError("read-only reference store")
        atomic_put(self.root / key, value.to_bytes())


def peak_rss():
    if sys.platform == "win32":
        import ctypes
        from ctypes import wintypes

        class Counters(ctypes.Structure):
            _fields_ = [("cb", wintypes.DWORD), ("PageFaultCount", wintypes.DWORD),
                        *[(name, ctypes.c_size_t) for name in ("PeakWorkingSetSize", "WorkingSetSize",
                          "QuotaPeakPagedPoolUsage", "QuotaPagedPoolUsage", "QuotaPeakNonPagedPoolUsage",
                          "QuotaNonPagedPoolUsage", "PagefileUsage", "PeakPagefileUsage")]]
        kernel = ctypes.WinDLL("kernel32", use_last_error=True)
        kernel.GetCurrentProcess.restype = wintypes.HANDLE
        kernel.K32GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
        kernel.K32GetProcessMemoryInfo.restype = wintypes.BOOL
        counters = Counters()
        counters.cb = ctypes.sizeof(counters)
        if not kernel.K32GetProcessMemoryInfo(kernel.GetCurrentProcess(), ctypes.byref(counters), counters.cb):
            raise ctypes.WinError(ctypes.get_last_error())
        return counters.PeakWorkingSetSize
    import resource
    value = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return value if sys.platform == "darwin" else value * 1024


def python_worker(base_url, output, origin, extent):
    start = time.perf_counter_ns()
    timings = dict(open_ns=0, hydrate_ns=0, decode_ns=0, process_ns=0, write_ns=0)
    encoded = {}
    buffer = default_buffer_prototype().buffer
    begin = time.perf_counter_ns()
    for key in (".zarray", ".zgroup", "zarr.json"):
        try:
            with urllib.request.urlopen(base_url + "/" + key, timeout=30) as response:
                encoded[key] = buffer.from_bytes(response.read())
        except urllib.error.HTTPError as error:
            if error.code != 404:
                raise
    source = zarr.open_array(zarr.storage.MemoryStore(store_dict=encoded), mode="r")
    assert source.dtype == np.uint8 and source.chunks == (64, 64, 64)
    timings["open_ns"] = time.perf_counter_ns() - begin
    histogram = np.zeros(256, dtype=np.int64)
    count = checksum = shards = 0
    result = None
    for x in range(0, extent[0], 8):
        for y in range(0, extent[1], 32):
            for z in range(0, extent[2], 32):
                offset = [x, y, z]
                tile_origin = [o + i for o, i in zip(origin, offset)]
                tile_extent = [min(s, n - i) for s, n, i in zip((8, 32, 32), extent, offset)]
                begin = time.perf_counter_ns()
                for a in range(tile_origin[0] // 64, (tile_origin[0] + tile_extent[0] - 1) // 64 + 1):
                    for b in range(tile_origin[1] // 64, (tile_origin[1] + tile_extent[1] - 1) // 64 + 1):
                        for c in range(tile_origin[2] // 64, (tile_origin[2] + tile_extent[2] - 1) // 64 + 1):
                            key = f"{a}/{b}/{c}"
                            if key not in encoded:
                                with urllib.request.urlopen(base_url + "/" + key, timeout=30) as response:
                                    encoded[key] = buffer.from_bytes(response.read())
                timings["hydrate_ns"] += time.perf_counter_ns() - begin
                begin = time.perf_counter_ns()
                tile = np.asarray(source[tuple(slice(o, o + n) for o, n in zip(tile_origin, tile_extent))])
                timings["decode_ns"] += time.perf_counter_ns() - begin
                begin = time.perf_counter_ns()
                values = tile.astype(np.float32) / np.float32(255)
                histogram += np.bincount(tile.ravel(), minlength=256)
                checksum += int(tile.sum())
                count += tile.size
                timings["process_ns"] += time.perf_counter_ns() - begin
                begin = time.perf_counter_ns()
                if result is None:
                    output.mkdir(exist_ok=False)
                    atomic_put(output / "pipeline-status.json", b'{"schema_version":1,"status":"incomplete"}')
                    result = zarr.create_array(store=SyncedStore(output), shape=tuple(extent), dtype="float32",
                                               chunks=(2, 16, 16), shards=(8, 32, 32),
                                               compressors=[zarr.codecs.ZstdCodec(level=3)],
                                               config={"write_empty_chunks": True})
                result[tuple(slice(i, i + n) for i, n in zip(offset, tile_extent))] = values
                timings["write_ns"] += time.perf_counter_ns() - begin
                shards += 1
    begin = time.perf_counter_ns()
    result.attrs["processing"] = dict(operation="uint8_to_float32", roi_origin=origin, roi_shape=extent,
                                      scale=1 / 255, axis_order="preserved; no physical-coordinate interpretation")
    atomic_put(output / "pipeline-status.json", json.dumps(dict(schema_version=1, status="complete",
               shape=extent, voxels=int(count), shards=shards)).encode())
    timings["write_ns"] += time.perf_counter_ns() - begin
    timings["total_ns"] = time.perf_counter_ns() - start
    timings["remote_decode_separated"] = True
    print(json.dumps(dict(voxels=int(count), input_checksum=checksum, shards=shards, histogram=histogram.tolist(),
                         completion="complete", timings=timings, peak_rss_bytes=peak_rss())))


def run(args):
    assert zarr.__version__ == "3.4.0" and np.__version__ == "2.5.3"
    report_path = args.output.resolve()
    if report_path.exists():
        raise FileExistsError(report_path)
    artifacts = report_path.parent / (report_path.stem + "-artifacts")
    artifacts.mkdir(parents=True, exist_ok=False)
    status = artifacts / "verification-status.json"
    write_json(status, {"status": "incomplete"})
    try:
        manifest, objects = prepare(args.work_dir.resolve(), args.download)
        values = zarr.open_array(str(args.work_dir.resolve()), mode="r")[:128, :128, :128]
        assert int(values.sum()) == 24039966
        binary, version = build_app(True)
        records = []

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_GET(self):
                body = objects.get(self.path)
                code = 200 if body is not None else 404
                body = body or b""
                records.append(dict(key=self.path, status=code, bytes=len(body)))
                self.send_response(code)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        cases = []
        try:
            for label, origin, extent in [("aligned", [0, 0, 0], [128, 128, 128]),
                                           ("nonaligned", [1, 2, 3], [125, 124, 123])]:
                samples = []
                for pair in range(args.trials + 1):
                    # AB, BA, AB... after an unmeasured warmup for both paths.
                    order = ["moonbit", "python"] if pair % 2 else ["python", "moonbit"]
                    for implementation in order:
                        trial = "warmup" if pair == 0 else f"pair-{pair}"
                        stem = f"{label}-{trial}-{implementation}"
                        output = artifacts / (stem + ".zarr")
                        url = f"http://127.0.0.1:{server.server_port}"
                        if implementation == "moonbit":
                            invocation = [str(binary), url, "", str(output), *map(str, origin), *map(str, extent)]
                        else:
                            invocation = [sys.executable, str(Path(__file__).resolve()), "--worker", url,
                                          str(output), *map(str, origin), *map(str, extent)]
                        records.clear()
                        start = time.perf_counter_ns()
                        process = subprocess.run(invocation, cwd=PROJECT, capture_output=True, text=True,
                                                 encoding="utf-8", errors="replace", timeout=600)
                        wall_ms = (time.perf_counter_ns() - start) / 1e6
                        (artifacts / (stem + ".stdout.log")).write_text(process.stdout, encoding="utf-8")
                        (artifacts / (stem + ".stderr.log")).write_text(process.stderr, encoding="utf-8")
                        if process.returncode:
                            raise RuntimeError(f"{stem} failed: {process.stderr}")
                        summary = json.loads(process.stdout.strip().splitlines()[-1])
                        verification = verify_output(output, values, origin, extent, summary)
                        marker = json.loads((output / "pipeline-status.json").read_text(encoding="utf-8"))
                        assert marker["status"] == "complete" and marker["shape"] == extent
                        check = json.loads(command([str(binary), "--check", str(output)], APP))
                        assert check["status"] == "complete"
                        assert len(records) == 11 and sum(r["bytes"] for r in records) == 301835
                        timings = summary["timings"]
                        assert all(timings[k] >= 0 for k in ("open_ns", "hydrate_ns", "decode_ns", "process_ns", "write_ns"))
                        assert sum(timings[k] for k in ("open_ns", "hydrate_ns", "decode_ns", "process_ns", "write_ns")) <= timings["total_ns"]
                        assert summary["peak_rss_bytes"] > 0
                        sample = dict(implementation=implementation, pair=pair, wall_ms=wall_ms,
                                      timings=timings, peak_rss_bytes=summary["peak_rss_bytes"],
                                      requests=len(records), transferred_bytes=301835, output=output.name,
                                      output_bytes=sum(p.stat().st_size for p in output.rglob("*") if p.is_file()),
                                      verification=verification)
                        write_json(artifacts / (stem + ".requests.json"), records)
                        if pair:
                            samples.append(sample)
                        print(f"{label}/{trial}/{implementation}: {wall_ms:.2f} ms; every value verified", flush=True)
                summaries = {}
                for implementation in ("moonbit", "python"):
                    selected = [s for s in samples if s["implementation"] == implementation]
                    summaries[implementation] = dict(median_wall_ms=statistics.median(s["wall_ms"] for s in selected),
                        max_peak_rss_bytes=max(s["peak_rss_bytes"] for s in selected),
                        median_stage_ms={k: statistics.median(s["timings"][k] for s in selected) / 1e6
                                         for k in ("open_ns", "hydrate_ns", "decode_ns", "process_ns", "write_ns", "total_ns")})
                cases.append(dict(name=label, origin=origin, extent=extent, summaries=summaries, samples=samples))
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)
        names = command(["git", "ls-files", "--cached", "--others", "--exclude-standard"], PROJECT).splitlines()
        hashes = {name: hashlib.sha256((PROJECT / name).read_bytes()).hexdigest() for name in sorted(names)
                  if name.endswith((".mbt", ".py", ".c", "moon.mod", "moon.pkg")) and (PROJECT / name).is_file()}
        report = dict(schema_version=1, status="verified", timestamp_utc=datetime.now(timezone.utc).isoformat(),
            platform=platform.platform(), python=platform.python_version(), zarr=zarr.__version__, numpy=np.__version__,
            toolchain=command(["moon", "version", "--all"], PROJECT).strip(),
            commit=command(["git", "rev-parse", "HEAD"], PROJECT).strip(),
            working_tree=command(["git", "status", "--short"], PROJECT).splitlines(), implementation_sha256=hashes,
            dependency=f"zlhahaha/zarr@{version}; explicit source workspace",
            manifest=manifest, manifest_sha256=hashlib.sha256(MANIFEST.read_bytes()).hexdigest(),
            executable_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(), trials_per_case=args.trials,
            artifacts=artifacts.name, warmups_per_implementation_per_case=1,
            scope="paired alternating fresh processes, release native vs task-specific zarr-python reference; same hash-pinned CT ROI, tile/shard layout, uint8->float32 /255, histogram, provenance, Zstd3, single-key data sync+replace and completion marker; loopback HTTP encoded-object cache; no WAN/cold-disk claim; wall includes process startup/imports; internal stages exclude startup/imports; decode includes typed assembly, hydrate includes cache and encoded staging; write includes compression, index encoding, filesystem operations and data sync; RSS is OS process high-water including each runtime, Python imports and arrays, not parent oracle/server; no total-memory bound or broad language ranking",
            cases=cases)
        with report_path.open("x", encoding="utf-8") as stream:
            stream.write(json.dumps(report, indent=2) + "\n")
        write_json(status, {"status": "verified", "report": report_path.name})
        print(f"verified paired report: {report_path}", flush=True)
    except BaseException as error:
        write_json(status, {"status": "failed", "error": str(error)})
        raise


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--worker":
        if len(sys.argv) != 10:
            raise ValueError("worker requires URL OUTPUT O0 O1 O2 N0 N1 N2")
        python_worker(sys.argv[2], Path(sys.argv[3]), list(map(int, sys.argv[4:7])), list(map(int, sys.argv[7:10])))
    else:
        parser = argparse.ArgumentParser(description=__doc__)
        parser.add_argument("--download", action="store_true")
        parser.add_argument("--work-dir", type=Path, default=PROJECT / "_build/real-scan-data")
        parser.add_argument("--output", type=Path, default=PROJECT / "_build/paired-volume.json")
        parser.add_argument("--trials", type=int, default=5)
        args = parser.parse_args()
        if not 1 <= args.trials <= 10:
            parser.error("trials must be in 1..10")
        run(args)
