"""Run authenticated MoonBit reads against an isolated real MinIO process.

Build the pinned upstream server separately; see docs/REMOTE.md. No personal
AWS credentials, cloud bucket, Docker image, or upstream binary is required.
"""
from __future__ import annotations

import argparse
from contextlib import contextmanager
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request
from urllib.error import HTTPError

import boto3
from botocore.config import Config

PROJECT = Path(__file__).resolve().parents[1]
FIXTURES = PROJECT / "integration" / "fixtures" / "zarr-python"
MINIO_MODULE = "v0.0.0-20251015172955-9e49d5e7a648"


def free_port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


@contextmanager
def relay(upstream_port, mode="normal"):
    """Observe real responses; inject only timeout/one transient error cases."""
    records = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass  # Never log Authorization headers or disposable credentials.

        def do_GET(self):
            record = {"path": self.path, "range": self.headers.get("Range"),
                      "if_match": self.headers.get("If-Match"), "status": None}
            records.append(record)
            if mode == "transient" and len(records) == 1:
                record["status"] = 503
                self.send_response(503)
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            if mode == "slow":
                time.sleep(1.0)
            connection = http.client.HTTPConnection("127.0.0.1", upstream_port, timeout=5)
            try:
                # Preserve signed Host/Range/If-Match exactly. MinIO, rather
                # than this relay, verifies every successful request signature.
                headers = {k: v for k, v in self.headers.items() if k.lower() != "connection"}
                connection.request("GET", self.path, headers=headers)
                response = connection.getresponse()
                body = response.read()
                record["status"] = response.status
                record["content_range"] = response.getheader("Content-Range")
                self.send_response(response.status)
                for key, value in response.getheaders():
                    if key.lower() not in {"connection", "transfer-encoding", "content-length", "server", "date"}:
                        self.send_header(key, value)
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                pass  # Expected when MoonBit cancels the deliberately slow request.
            finally:
                connection.close()

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = False  # server_close waits for delayed request threads.
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}", records
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def run_case(endpoint, scenario, base_env, *, secret=None, access=None):
    env = dict(base_env, ZARR_S3_ENDPOINT=endpoint, ZARR_S3_CASE=scenario)
    if secret is not None:
        env["ZARR_S3_SECRET_KEY"] = secret
    if access is not None:
        env["ZARR_S3_ACCESS_KEY"] = access
    result = subprocess.run(
        ["moon", "run", "--target", "native", "cmd/s3_integration"],
        cwd=PROJECT, env=env, capture_output=True, text=True,
        encoding="utf-8", errors="replace", timeout=90,
    )
    if result.returncode:
        raise RuntimeError(f"MoonBit {scenario} case failed:\n{result.stdout}\n{result.stderr}")
    print(result.stdout.strip())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--minio-bin", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    binary = args.minio_bin.resolve(strict=True)
    version = subprocess.check_output([str(binary), "--version"], text=True).strip()
    build_info = subprocess.check_output(["go", "version", "-m", str(binary)], text=True)
    if MINIO_MODULE not in build_info:
        raise RuntimeError("build MinIO from the pinned official release documented in REMOTE.md")
    access = "zarrtest" + secrets.token_hex(8)
    secret = secrets.token_hex(24)
    bucket = "zarr-integration"
    port, console_port = free_port(), free_port()
    while console_port == port:
        console_port = free_port()
    endpoint = f"http://127.0.0.1:{port}"
    scratch = PROJECT / "_build" / "remote-tests"
    scratch.mkdir(parents=True, exist_ok=True)
    base_env = dict(os.environ, ZARR_S3_ACCESS_KEY=access, ZARR_S3_SECRET_KEY=secret,
                    ZARR_S3_BUCKET=bucket, AWS_EC2_METADATA_DISABLED="true")
    with tempfile.TemporaryDirectory(prefix="minio-", dir=scratch) as directory:
        root = Path(directory)
        env = dict(os.environ, MINIO_ROOT_USER=access, MINIO_ROOT_PASSWORD=secret,
                   MINIO_BROWSER="off", MINIO_UPDATE="off")
        with (root / "server.log").open("wb") as log:
            process = subprocess.Popen(
                [str(binary), "server", "--address", f"127.0.0.1:{port}",
                 "--console-address", f"127.0.0.1:{console_port}", str(root / "data")],
                env=env, stdout=log, stderr=subprocess.STDOUT,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
            try:
                opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
                for _ in range(100):
                    if process.poll() is not None:
                        raise RuntimeError("MinIO exited before readiness; inspect test setup")
                    try:
                        with opener.open(endpoint + "/minio/health/live", timeout=0.5) as response:
                            if response.status == 200:
                                break
                    except OSError:
                        time.sleep(0.1)
                else:
                    raise RuntimeError("MinIO readiness timed out")
                client = boto3.client(
                    "s3", endpoint_url=endpoint, region_name="us-east-1",
                    aws_access_key_id=access, aws_secret_access_key=secret,
                    config=Config(signature_version="s3v4", proxies={},
                                  s3={"addressing_style": "path"}),
                )
                client.create_bucket(Bucket=bucket)
                for name, fixture in [("ordinary", "v2_gzip_u8"),
                                      ("start", "v3_shard_start_u8"),
                                      ("end", "v3_shard_end_gzip_u16")]:
                    source = FIXTURES / (fixture + ".zarr")
                    for path in sorted(source.rglob("*")):
                        if path.is_file():
                            key = f"dataset/{name}/{path.relative_to(source).as_posix()}"
                            client.put_object(Bucket=bucket, Key=key, Body=path.read_bytes())
                client.put_object(Bucket=bucket, Key="dataset/missing-shard/zarr.json",
                                  Body=(FIXTURES / "v3_shard_start_u8.zarr" / "zarr.json").read_bytes())
                group = b'{"zarr_format":3,"node_type":"group","attributes":{}}'
                for key in ("catalog/zarr.json", "catalog/nested/zarr.json"):
                    client.put_object(Bucket=bucket, Key=key, Body=group)
                for name, fixture in [("start", "v3_shard_start_u8"), ("end", "v3_shard_end_gzip_u16"),
                                      ("μ & 图", "v3_shard_start_u8"), ("nested/cube", "v3_shard_start_u8")]:
                    source = FIXTURES / (fixture + ".zarr")
                    for path in source.rglob("*"):
                        if path.is_file():
                            client.put_object(Bucket=bucket, Key=f"catalog/{name}/{path.relative_to(source).as_posix()}",
                                              Body=path.read_bytes())
                client.put_object(Bucket=bucket, Key="catalog/unmarked/notes.txt", Body=b"not a node")
                try:
                    with opener.open(endpoint + f"/{bucket}/dataset/ordinary/.zarray", timeout=5):
                        raise AssertionError("private fixture unexpectedly permits anonymous reads")
                except HTTPError as error:
                    assert error.code == 403
                with relay(port) as (url, records):
                    run_case(url, "valid", base_env)
                    successful = list(records)
                    listings = [r for r in successful if "list-type=2" in r["path"]]
                    assert len(listings) >= 3 and all(r["status"] == 200 for r in listings)
                    assert any("continuation-token=" in r["path"] for r in listings), "pagination not exercised"
                    ranges = [r for r in successful if r["range"] and r["status"] == 206]
                    assert any(r["range"].startswith("bytes=-") for r in ranges), "no suffix index read"
                    assert any(not r["range"].startswith("bytes=-") for r in ranges), "no prefix/payload read"
                    assert any(r["if_match"] for r in ranges), "no ETag conditional payload read"
                    assert all(r.get("content_range") for r in ranges), "missing real Content-Range"
                    shard_reads = [r for r in successful if "/c/" in r["path"] and r["status"] != 404]
                    assert shard_reads and all(r["range"] and r["status"] == 206 for r in shard_reads)
                    assert any(r["status"] == 404 for r in successful), "missing data not exercised"
                    records.clear()
                    run_case(url, "denied", base_env, secret="wrong-test-secret")
                    assert records and all(r["status"] == 403 for r in records)
                    records.clear()
                    run_case(url, "denied", base_env, access="unknown-test-access")
                    assert records and all(r["status"] == 403 for r in records)
                with relay(port, "transient") as (url, records):
                    run_case(url, "retry", base_env)
                    first_key = records[0]["path"]
                    attempts = [r["status"] for r in records if r["path"] == first_key]
                    assert attempts == [503, 200], attempts
                with relay(port, "slow") as (url, records):
                    started = time.monotonic()
                    run_case(url, "timeout", base_env)
                    elapsed = time.monotonic() - started
                    # Fail-fast Result discovery stops after the first failed object.
                    paths = {r["path"] for r in records}
                    assert len(paths) == 1 and len(records) == 2
                    assert all(sum(r["path"] == path for r in records) == 2 for path in paths)
                    assert elapsed < 15, "request timeout did not bound the test"
                # Independent application: real private S3 3D shard reads,
                # crop/normalize, local sharded output, full Python comparison.
                pipeline_env = dict(os.environ, ZARR_ACCESS_KEY=access, ZARR_SECRET_KEY=secret,
                                    ZARR_ENDPOINT=endpoint, ZARR_ALLOW_INSECURE_HTTP="true",
                                    ZARR_REGION="us-east-1")
                with relay(port) as (url, pipeline_records):
                    pipeline_env["ZARR_ENDPOINT"] = url
                    subprocess.run([sys.executable, str(PROJECT / "scripts/verify_volume_pipeline.py"),
                                    "--source", "--s3-endpoint", endpoint, "--s3-bucket", bucket,
                                    "--output", str(PROJECT / "_build/volume-pipeline-minio.json")],
                                   cwd=PROJECT, env=pipeline_env, check=True, timeout=600)
                    assert any(r["status"] == 206 and r["range"] for r in pipeline_records)
                report = {"minio": version, "minio_module": MINIO_MODULE, "boto3": boto3.__version__,
                          "source_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=PROJECT, text=True).strip(),
                          "tracked_changes": subprocess.check_output(["git", "status", "--porcelain"], cwd=PROJECT, text=True).splitlines(),
                          "toolchain": subprocess.check_output(["moon", "version", "--all"], text=True).strip(),
                          "range_requests": len(ranges), "missing_fills": True,
                          "bad_secret_403": True, "unknown_key_403": True,
                          "anonymous_read_403": True,
                          "transient_attempts_per_object": 2, "timeout_attempts_per_object": 2,
                          "timeout_discovery_requests": 2,
                          "signed_listing_requests": len(listings), "unicode_paths": True,
                          "independent_sharded_volume_pipeline": True,
                          "scope": "isolated private MinIO; no production AWS or STS certification"}
                if args.output:
                    args.output.parent.mkdir(parents=True, exist_ok=True)
                    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
                print(f"MinIO authenticated integration passed: {len(ranges)} real Range responses")
            finally:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=10)


if __name__ == "__main__":
    main()
