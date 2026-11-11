"""Exercise real application completion checks after late I/O failure or termination."""
from __future__ import annotations

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
import tempfile
import threading

import numpy as np
import numcodecs
import zarr

from verify_real_volume_pipeline import build_app
from verify_volume_pipeline import APP, PROJECT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if args.output and args.output.exists():
        raise FileExistsError(args.output)
    binary, _ = build_app(True)
    scratch = PROJECT / "_build/pipeline-failure-checks"
    scratch.mkdir(parents=True, exist_ok=True)
    passed = []
    with tempfile.TemporaryDirectory(dir=scratch) as temporary:
        root = Path(temporary)
        source = root / "input.zarr"
        values = (np.arange(17 * 65 * 65, dtype=np.uint32) % 256).astype(np.uint8).reshape(17, 65, 65)
        array = zarr.create_array(str(source), shape=values.shape, chunks=(8, 32, 32), dtype="uint8",
                                  zarr_format=2, compressors=[numcodecs.GZip(level=1)])
        array[:] = values
        state = {}
        paused = threading.Event()
        release = threading.Event()

        class Handler(BaseHTTPRequestHandler):
            protocol_version = "HTTP/1.1"

            def handle(self):
                try:
                    super().handle()
                except (ConnectionResetError, ConnectionAbortedError, BrokenPipeError):
                    # Expected when deliberately terminating the reader.
                    pass

            def do_GET(self):
                path = source / self.path.lstrip("/")
                body = path.read_bytes() if path.is_file() else b""
                code = 200 if path.is_file() else 404
                output = state.get("output")
                if code == 200 and output and (output / "c/0/0/0").is_file() and not state.get("injected"):
                    state["injected"] = True
                    if state["mode"] == "read-failure":
                        code, body = 403, b""
                    elif state["mode"] == "write-failure":
                        # A directory at the next shard key forces replacement
                        # to fail after an earlier shard has already committed.
                        (output / "c/0/0/1").mkdir()
                    elif state["mode"] == "termination":
                        paused.set()
                        release.wait(timeout=30)
                try:
                    self.send_response(code)
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                    pass

            def log_message(self, *_):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        def invoke(parts, success):
            result = subprocess.run([str(binary), *map(str, parts)], cwd=APP, capture_output=True,
                                    text=True, encoding="utf-8", errors="replace", timeout=60)
            assert (result.returncode == 0) == success, result.stdout + result.stderr
            return result

        def check(path, success):
            invoke(["--check", path], success)

        def invocation(output, remote=True):
            return [f"http://127.0.0.1:{server.server_port}" if remote else str(source), "", str(output),
                    "0", "0", "0", "17", "65", "65"]

        try:
            for mode in ("read-failure", "write-failure", "termination"):
                output = root / (mode + ".zarr")
                state.clear()
                state.update(mode=mode, output=output)
                if mode == "termination":
                    process = subprocess.Popen([str(binary), *invocation(output)], cwd=APP,
                                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    try:
                        assert paused.wait(timeout=30), "failed to reach a mid-pipeline pause"
                        process.terminate()
                        process.communicate(timeout=10)
                        assert process.returncode != 0
                    finally:
                        release.set()
                        if process.poll() is None:
                            process.kill()
                            process.communicate(timeout=10)
                else:
                    invoke(invocation(output), False)
                assert state.get("injected") and (output / "c/0/0/0").is_file()
                marker = json.loads((output / "pipeline-status.json").read_text(encoding="utf-8"))
                assert marker["status"] == "incomplete"
                check(output, False)
                before = {p.relative_to(output): p.read_bytes() for p in output.rglob("*") if p.is_file()}
                invoke(invocation(output, remote=False), False)
                assert before == {p.relative_to(output): p.read_bytes() for p in output.rglob("*") if p.is_file()}
                passed.append(mode + ": incomplete, rejected, preserved")
                print(passed[-1], flush=True)
            state.clear()
            output = root / "complete.zarr"
            invoke(invocation(output, remote=False), True)
            check(output, True)
            metadata_path = output / "zarr.json"
            original_metadata = metadata_path.read_bytes()
            metadata = json.loads(original_metadata)
            metadata["chunk_grid"]["configuration"]["chunk_shape"] = [16, 32, 32]
            metadata_path.write_text(json.dumps(metadata), encoding="utf-8")
            check(output, False)
            metadata_path.write_bytes(original_metadata)
            passed.append("mismatched shard layout rejected despite complete marker")
            missing = output / "c/0/0/0"
            missing.unlink()
            check(output, False)
            missing.mkdir()
            check(output, False)
            passed.append("missing/nonregular shard rejected despite complete marker")
            absent = root / "no-marker.zarr"
            absent.mkdir()
            check(absent, False)
            (absent / "pipeline-status.json").write_text("{", encoding="utf-8")
            check(absent, False)
            passed.append("missing and malformed markers rejected")
        finally:
            release.set()
            server.shutdown()
            server.server_close()
            thread.join(timeout=5)
    report = dict(status="verified", scenarios=passed,
                  scope="application-level completion detection; no resume, multi-shard transaction, concurrent writer or power-loss guarantee")
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with args.output.open("x", encoding="utf-8") as stream:
            stream.write(json.dumps(report, indent=2) + "\n")
    print("pipeline completion/failure checks passed", flush=True)


if __name__ == "__main__":
    main()
