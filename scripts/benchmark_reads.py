"""Generate independent stores and measure a release-built MoonBit reader.

Each measurement is a fresh process; timings exclude open/verification and
memory is the OS high-water mark of that process, not Python or compiler RSS.
"""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import platform
import statistics
import subprocess
import sys

PROJECT = Path(__file__).resolve().parents[1]
DEPS = PROJECT / ".interop-deps"
if DEPS.exists():
    sys.path.insert(0, str(DEPS))

import numpy as np
import zarr
from zarr.codecs import BytesCodec, Crc32cCodec, GzipCodec, ShardingCodec


def generate(root, quick):
    # New directories only; never overwrite user stores or past measurements.
    root.mkdir(parents=True, exist_ok=False)
    dim = 512 if quick else 4096
    stress_dim = 256 if quick else 1024
    configs = [
        ("v2_gzip", dim, 64, None, 2),
        ("v3_raw", dim, 64, None, 3),
        ("v3_gzip", dim, 64, None, 3),
        ("v3_shard_gzip", dim, 64, 256 if quick else 512, 3),
        ("v3_shard_index_stress", stress_dim, 8, stress_dim, 3),
    ]
    inventory = []
    for name, size, inner, outer, version in configs:
        kwargs = dict(store=str(root / f"{name}.zarr"), shape=(size, size),
                      chunks=(outer or inner, outer or inner), dtype="uint16",
                      fill_value=0, zarr_format=version)
        if version == 2:
            from numcodecs import GZip
            kwargs["compressor"] = GZip(level=1)
            array = zarr.create(**kwargs)
        else:
            codecs = [BytesCodec(endian="little")]
            if name.endswith("gzip"):
                codecs.append(GzipCodec(level=1))
            if outer:
                kwargs.update(serializer=ShardingCodec(
                    chunk_shape=(inner, inner), codecs=codecs,
                    index_codecs=[BytesCodec(endian="little"), Crc32cCodec()],
                    index_location="end"), compressors=[], filters=[])
            else:
                kwargs.update(serializer=codecs[0], compressors=codecs[1:], filters=[])
            array = zarr.create_array(**kwargs)
        # Bounded generation blocks; reader peak memory excludes this process.
        for row in range(0, size, outer or 256):
            rows = np.arange(row, min(row + (outer or 256), size), dtype=np.uint32)[:, None]
            cols = np.arange(size, dtype=np.uint32)[None, :]
            array[row:row + len(rows), :] = ((rows * 17 + cols * 31) % 65521 + 1).astype(np.uint16)
        files = sorted(p for p in (root / f"{name}.zarr").rglob("*") if p.is_file())
        digest = hashlib.sha256()
        for path in files:
            digest.update(path.relative_to(root).as_posix().encode())
            digest.update(path.read_bytes())
        inventory.append(dict(name=name, shape=[size, size], chunk_shape=[inner, inner],
                              shard_shape=[outer, outer] if outer else None,
                              logical_bytes=size * size * 2,
                              stored_bytes=sum(p.stat().st_size for p in files),
                              sha256=digest.hexdigest()))
        print(f"generated {name}", flush=True)
    (root / "inventory.json").write_text(json.dumps(inventory, indent=2) + "\n", encoding="utf-8")


def run(args):
    if zarr.__version__ != "3.4.0" or np.__version__ != "2.5.3":
        raise RuntimeError("install pinned zarr==3.4.0 numpy==2.5.3")
    root = args.work_dir.resolve()
    if not args.reuse:
        generate(root, args.quick)
    inventory = json.loads((root / "inventory.json").read_text(encoding="utf-8"))
    if inventory[0]["shape"] != ([512, 512] if args.quick else [4096, 4096]):
        raise ValueError("--reuse profile must match the generated dataset profile")
    if args.output.exists():
        raise FileExistsError(f"refusing to overwrite {args.output}")
    if not args.binary:
        subprocess.run(["moon", "run", "--target", "native", "--release", "--build-only",
                        "cmd/benchmark"], cwd=PROJECT, check=True)
    binary = args.binary or PROJECT / "_build/native/release/build/cmd/benchmark/benchmark.exe"
    if not binary.is_file():
        raise FileNotFoundError(binary)
    rows = []
    for dataset in inventory:
        stress = "stress" in dataset["name"]
        sizes = [128] if args.quick else ([256] if stress else [256, 1024, 2048])
        for side in sizes:
            modes = ["off", "on"] if dataset["shard_shape"] else ["on"]
            samples = {mode: [] for mode in modes}
            for trial in range(args.trials + 1):
                # Alternate order to reduce simple ordering/page-cache bias.
                for mode in (modes if trial % 2 == 0 else list(reversed(modes))):
                    command = [str(binary.resolve()), str(root / f"{dataset['name']}.zarr"),
                               "7", "11", str(side), mode]
                    output = subprocess.run(command, cwd=PROJECT, check=True, capture_output=True,
                                            text=True, timeout=300).stdout
                    sample = json.loads(output.strip())
                    if sample["read_ns"] <= 0 or sample["peak_rss_bytes"] <= 0:
                        raise RuntimeError("invalid OS measurements")
                    inner = dataset["chunk_shape"][0]
                    touched = ((7 + side - 1) // inner - 7 // inner + 1) * (
                        (11 + side - 1) // inner - 11 // inner + 1)
                    if dataset["shard_shape"]:
                        outer = dataset["shard_shape"][0]
                        shards = ((7 + side - 1) // outer - 7 // outer + 1) * (
                            (11 + side - 1) // outer - 11 // outer + 1)
                        expected_reads = touched if mode == "off" else shards
                        if sample["index_reads"] != expected_reads or sample["payload_reads"] != touched:
                            raise RuntimeError("unexpected shard range-read counts")
                        if sample["peak_cached_index_bytes"] > 16777216:
                            raise RuntimeError("index cache exceeds configured cap")
                    if trial:  # Discard first trial per case/mode; OS cache is not flushed.
                        samples[mode].append(sample)
            for mode in modes:
                values = samples[mode]
                row = dict(dataset=dataset["name"], origin=[7, 11], extent=[side, side],
                           cache_mode=mode, samples=values,
                           median_ms=statistics.median(s["read_ns"] for s in values) / 1e6,
                           min_ms=min(s["read_ns"] for s in values) / 1e6,
                           max_ms=max(s["read_ns"] for s in values) / 1e6,
                           max_peak_rss_bytes=max(s["peak_rss_bytes"] for s in values))
                rows.append(row)
                print(f"{dataset['name']} {side} {mode}: {row['median_ms']:.3f} ms, "
                      f"{row['max_peak_rss_bytes']/1048576:.2f} MiB peak", flush=True)
            if len(modes) == 2 and samples["off"][0]["checksum"] != samples["on"][0]["checksum"]:
                raise RuntimeError("cache changes result")
    source_digest = hashlib.sha256()
    source_paths = set(subprocess.check_output(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard"],
        cwd=PROJECT, text=True).splitlines())
    source_paths.update(p.relative_to(PROJECT).as_posix() for p in (PROJECT / "cmd/benchmark").iterdir())
    for name in sorted(source_paths):
        if name.endswith((".mbt", ".c")):
            source_digest.update(name.encode())
            source_digest.update((PROJECT / name).read_bytes())
    report = dict(schema_version=1, timestamp=datetime.now(timezone.utc).isoformat(),
                  platform=platform.platform(), machine=platform.machine(), processor=platform.processor(),
                  toolchain=subprocess.check_output(["moon", "version", "--all"], text=True),
                  commit=subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=PROJECT, text=True).strip(),
                  binary_sha256=hashlib.sha256(binary.read_bytes()).hexdigest(),
                  source_sha256=source_digest.hexdigest(),
                  tracked_changes=subprocess.check_output(["git", "status", "--porcelain"],
                                                          cwd=PROJECT, text=True).splitlines(),
                  trials=args.trials, discarded_trials=1, quick=args.quick,
                  memory_metric="OS process high-water RSS / Windows peak working set",
                  page_cache="not flushed; warmup discarded; not a cold disk benchmark",
                  datasets=inventory, results=rows)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--work-dir", type=Path, default=PROJECT / "_build/bench-data")
    parser.add_argument("--output", type=Path, default=PROJECT / "_build/bench-results.json")
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--trials", type=int, default=5)
    parser.add_argument("--quick", action="store_true")
    parser.add_argument("--reuse", action="store_true", help="reuse this script's generated datasets")
    args = parser.parse_args()
    if args.trials < 1 or args.trials > 20:
        parser.error("trials must be in 1..20")
    run(args)
