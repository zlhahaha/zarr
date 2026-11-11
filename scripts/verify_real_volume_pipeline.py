"""Convert hash-pinned bonsai CT ROIs with MoonBit; verify every value in Python.

No upstream dataset bytes are committed. Only --download permits downloads.
The timed path replays the original compressed objects over loopback HTTP and
runs the release executable directly; build/download/oracle time is excluded.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import platform
import re
import statistics
import subprocess
import threading
import time

import numpy as np
import zarr

from benchmark_real_scan import MANIFEST, prepare
from verify_volume_pipeline import APP, PROJECT, source_workspace


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")


def command(parts, cwd):
    result = subprocess.run(parts, cwd=cwd, capture_output=True, text=True,
                            encoding="utf-8", errors="replace", timeout=600)
    if result.returncode:
        raise RuntimeError(f"command failed: {parts[0:4]}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def build_app(source):
    cwd = PROJECT if source else APP
    with source_workspace(source):
        command(["moon", "check", "--target", "native", "--deny-warn"], cwd)
        stdout = command(["moon", "run", "--target", "native", "--release",
                          "--build-only", str(APP)], cwd)
        # Consume the toolchain's artifact path, rather than guessing .exe paths
        # or accidentally selecting an old binary from a different build mode.
        artifacts = []
        for line in stdout.splitlines():
            try:
                artifacts.extend(json.loads(line).get("artifacts_path", []))
            except (ValueError, AttributeError):
                continue
        if len(artifacts) != 1 or not Path(artifacts[0]).is_file():
            raise RuntimeError(f"expected one executable artifact from moon: {stdout}")
        version = re.search(r'"zlhahaha/zarr@([^"\s]+)"', (APP / "moon.mod").read_text())[1]
        if not source:
            installed = APP / ".mooncakes/zlhahaha/zarr"
            if installed.resolve() == PROJECT.resolve() or f'version = "{version}"' not in (installed / "moon.mod").read_text():
                raise RuntimeError("registry dependency does not match the pinned application version")
        return Path(artifacts[0]), version


def verify_output(output, values, origin, extent, summary):
    roi = values[tuple(slice(o, o + n) for o, n in zip(origin, extent))]
    expected = roi.astype(np.float32) / np.float32(255)
    result = zarr.open_array(str(output), mode="r")
    actual = result[:]
    # Exact comparison: both sides explicitly compute float32(value)/float32(255).
    np.testing.assert_array_equal(actual, expected)
    assert result.shape == tuple(extent) and result.dtype == np.dtype("float32")
    assert result.metadata.zarr_format == 3
    assert result.chunks == (2, 16, 16) and result.shards == (8, 32, 32)
    metadata = json.loads((output / "zarr.json").read_text(encoding="utf-8"))
    shard_codec = metadata["codecs"][0]
    assert shard_codec["name"] == "sharding_indexed"
    assert any(codec["name"] == "zstd" and codec["configuration"]["level"] == 3
               for codec in shard_codec["configuration"]["codecs"])
    attrs = result.attrs["processing"]
    assert attrs["operation"] == "uint8_to_float32"
    assert attrs["roi_origin"] == origin and attrs["roi_shape"] == extent
    assert attrs["scale"] == 1 / 255
    assert attrs["axis_order"] == "preserved; no physical-coordinate interpretation"
    marker = json.loads((output / "pipeline-status.json").read_text(encoding="utf-8"))
    assert marker["schema_version"] == 1 and marker["status"] == "complete"
    assert marker["shape"] == extent and marker["voxels"] == roi.size
    expected_shards = int(np.prod([(n + s - 1) // s for n, s in zip(extent, (8, 32, 32))]))
    assert summary["shards"] == expected_shards
    assert marker["shards"] == expected_shards
    assert summary["voxels"] == roi.size and summary["input_checksum"] == int(roi.sum())
    assert summary["histogram"] == np.bincount(roi.ravel(), minlength=256).tolist()
    # Require every outer shard file, including edge/fill-only shards. Missing
    # chunks must not silently pass merely because their fill value is correct.
    expected_keys = {f"c/{i}/{j}/{k}" for i in range((extent[0] + 7) // 8)
                     for j in range((extent[1] + 31) // 32)
                     for k in range((extent[2] + 31) // 32)}
    actual_keys = {p.relative_to(output).as_posix() for p in (output / "c").rglob("*") if p.is_file()}
    assert actual_keys == expected_keys
    return {"voxels": int(roi.size), "input_checksum": int(roi.sum()),
            "histogram": summary["histogram"], "output_shards": expected_shards,
            "every_value_verified": True, "max_absolute_error": float(np.max(np.abs(actual - expected))),
            "metadata_and_provenance_verified": True, "all_shard_files_verified": True,
            "completion_marker_verified": True}


def run(args):
    if zarr.__version__ != "3.4.0" or np.__version__ != "2.5.3":
        raise RuntimeError("install zarr==3.4.0 numpy==2.5.3")
    report_path = args.output.resolve()
    if report_path.exists():
        raise FileExistsError(f"refusing to overwrite report: {report_path}")
    run_dir = report_path.parent / (report_path.stem + "-artifacts")
    run_dir.mkdir(parents=True, exist_ok=False)
    status_path = run_dir / "verification-status.json"
    write_json(status_path, {"status": "incomplete", "report": str(report_path),
                             "warning": "do not consume outputs without a successful verification report"})
    try:
        manifest, objects = prepare(args.work_dir.resolve(), args.download)
        # Decode only the pinned 128-cube, never the unavailable remainder of
        # the 256-cube whose absent files Python would interpret as fill values.
        array = zarr.open_array(str(args.work_dir.resolve()), mode="r")
        assert array.shape == (256, 256, 256) and array.chunks == (64, 64, 64)
        values = np.asarray(array[:128, :128, :128])
        assert values.dtype == np.uint8 and int(values.sum()) == 24039966
        binary, version = build_app(args.source)
        records = []

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def do_GET(self):
                body = objects.get(self.path)
                status = 200 if body is not None else 404
                # Pinned input is ordinary v2 chunks, not a sharded input.
                # Explicitly reject Range rather than pretending to support it.
                if self.headers.get("Range"):
                    body, status = b"", 416
                body = body or b""
                records.append({"key": self.path, "status": status, "bytes": len(body)})
                self.send_response(status)
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
                verification = None
                for trial in range(args.trials + 1):
                    name = "warmup" if trial == 0 else f"trial-{trial}"
                    output = run_dir / f"{label}-{name}.zarr"
                    records.clear()
                    started = time.perf_counter_ns()
                    result = subprocess.run([str(binary), f"http://127.0.0.1:{server.server_port}",
                                             "", str(output), *map(str, origin), *map(str, extent)],
                                            cwd=APP, capture_output=True, text=True,
                                            encoding="utf-8", errors="replace", timeout=600)
                    elapsed_ns = time.perf_counter_ns() - started
                    (run_dir / f"{label}-{name}.stdout.log").write_text(result.stdout, encoding="utf-8")
                    (run_dir / f"{label}-{name}.stderr.log").write_text(result.stderr, encoding="utf-8")
                    if result.returncode:
                        raise RuntimeError(f"application failed for {label}/{name}; see retained logs")
                    summary = json.loads(result.stdout.strip().splitlines()[-1])
                    verification = verify_output(output, values, origin, extent, summary)
                    command([str(binary), "--check", str(output)], APP)
                    assert summary["peak_rss_bytes"] > 0 and summary["timings"]["remote_decode_separated"]
                    metadata = [r for r in records if r["key"] in ("/.zarray", "/.zgroup", "/zarr.json")]
                    payload = [r for r in records if r["key"] not in ("/.zarray", "/.zgroup", "/zarr.json")]
                    assert len(metadata) == 3, "metadata must be pinned across all tiles"
                    assert all(r["status"] == 200 for r in payload)
                    expected_payloads = {"/" + entry["key"] for entry in manifest["objects"] if entry["key"] != ".zarray"}
                    assert {r["key"] for r in payload} == expected_payloads
                    sample = {"trial": name, "elapsed_ms": elapsed_ns / 1e6,
                              "output": output.name, "output_bytes": sum(p.stat().st_size for p in output.rglob("*") if p.is_file()),
                              "metadata_requests": len(metadata), "payload_requests": len(payload),
                              "unique_payload_objects": len({r["key"] for r in payload}),
                              "requests": len(records), "transferred_bytes": sum(r["bytes"] for r in records),
                              "timings": summary["timings"], "peak_rss_bytes": summary["peak_rss_bytes"],
                              "every_value_verified": True}
                    write_json(run_dir / f"{label}-{name}.requests.json", records)
                    if trial:
                        samples.append(sample)
                    print(f"real volume {label}/{name}: {verification['voxels']} values verified, "
                          f"{elapsed_ns / 1e6:.2f} ms, {len(payload)} payload GETs", flush=True)
                cases.append({"name": label, "origin": origin, "extent": extent,
                              "verification": verification, "samples": samples,
                              "median_ms": statistics.median(s["elapsed_ms"] for s in samples),
                              "min_ms": min(s["elapsed_ms"] for s in samples),
                              "max_ms": max(s["elapsed_ms"] for s in samples)})
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)
        evidence = {}
        names = command(["git", "ls-files", "--cached", "--others", "--exclude-standard"], PROJECT).splitlines()
        for name in sorted(names):
            if name.endswith((".mbt", ".c", "moon.mod", "moon.pkg", ".py")) and (PROJECT / name).is_file():
                evidence[name] = hashlib.sha256((PROJECT / name).read_bytes()).hexdigest()
        report = {"schema_version": 1, "status": "verified", "timestamp_utc": datetime.now(timezone.utc).isoformat(),
                  "platform": platform.platform(), "commit": command(["git", "rev-parse", "HEAD"], PROJECT).strip(),
                  "working_tree": command(["git", "status", "--short"], PROJECT).splitlines(),
                  "toolchain": command(["moon", "version", "--all"], PROJECT).strip(),
                  "dependency": f"zlhahaha/zarr@{version}",
                  "resolution": "explicit source workspace" if args.source else "registry; no local override",
                  "python": {"version": platform.python_version(), "zarr": zarr.__version__, "numpy": np.__version__},
                  "manifest_sha256": hashlib.sha256(MANIFEST.read_bytes()).hexdigest(), "manifest": manifest,
                  "implementation_sha256": evidence, "executable_sha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
                  "encoded_input_bytes": sum(len(body) for body in objects.values()),
                  "artifacts": run_dir.name, "warmups_per_case": 1, "trials_per_case": args.trials,
                  "peak_rss_bytes": max(s["peak_rss_bytes"] for c in cases for s in c["samples"]),
                  "scope": "fresh release process including launch, HTTP metadata/ROI reads, float32 normalization, histogram, shard writes, provenance and completion markers; excludes compilation, download, Python oracle and verification; exact objects replayed over loopback; default application cache policy; no WAN/cloud or general throughput claim; OS reader-process peak RSS includes native runtime/transport/decoder/buffers, excludes Python verifier/server; outputs are standard Zarr arrays, not complete OME-NGFF exports; author-maintained application, not external adoption",
                  "cases": cases}
        # Only publish a verified report once every case/trial passes. The
        # separate application directories alone are not completion markers.
        with report_path.open("x", encoding="utf-8") as stream:
            stream.write(json.dumps(report, indent=2) + "\n")
        write_json(status_path, {"status": "verified", "report": report_path.name})
        print(f"verified report: {report_path}", flush=True)
    except BaseException as error:
        write_json(status_path, {"status": "failed", "error": str(error),
                                 "warning": "do not consume outputs from this failed run"})
        raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", action="store_true", help="test checkout instead of the pinned registry release")
    parser.add_argument("--download", action="store_true", help="allow fetching missing hash-pinned source objects")
    parser.add_argument("--work-dir", type=Path, default=PROJECT / "_build/real-scan-data")
    parser.add_argument("--output", type=Path, default=PROJECT / "_build/real-volume-pipeline.json")
    parser.add_argument("--trials", type=int, default=3)
    args = parser.parse_args()
    if not 1 <= args.trials <= 10:
        parser.error("trials must be in 1..10")
    run(args)
