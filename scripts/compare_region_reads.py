"""Alternate two immutable benchmark binaries on identical existing datasets.

This controlled follow-up excludes generation/build time, discards one trial
per version and case, checks all values in each MoonBit process, and records
OS peak RSS and the exact binary hashes. No cold-cache or competitor claim.
"""
from pathlib import Path
import argparse
from datetime import datetime, timezone
import hashlib
import json
import platform
import statistics
import subprocess

PROJECT = Path(__file__).resolve().parents[1]


def main(args):
    if args.output.exists():
        raise FileExistsError(args.output)
    inventory = json.loads((args.work_dir / "inventory.json").read_text())
    binaries = {"baseline": args.baseline.resolve(), "optimized": args.optimized.resolve()}
    for binary in binaries.values():
        if not binary.is_file(): raise FileNotFoundError(binary)
    cases = [("v2_gzip", 2048), ("v3_raw", 2048), ("v3_gzip", 2048), ("v3_shard_gzip", 2048), ("v3_shard_index_stress", 256)]
    results = []
    for dataset, side in cases:
        samples = {label: [] for label in binaries}
        for trial in range(args.trials + 1):
            labels = list(binaries) if trial % 2 == 0 else list(reversed(binaries))
            pair = {}
            for label in labels:
                output = subprocess.check_output([str(binaries[label]), str((args.work_dir / f"{dataset}.zarr").resolve()), "7", "11", str(side), "on"], cwd=PROJECT, text=True, timeout=300)
                sample = json.loads(output)
                if sample["read_ns"] <= 0 or sample["peak_rss_bytes"] <= 0:
                    raise RuntimeError("invalid metrics")
                pair[label] = sample
                if trial: samples[label].append(sample)
            for metric in ("checksum", "result_bytes", "index_reads", "payload_reads", "index_bytes", "payload_bytes"):
                if pair["baseline"][metric] != pair["optimized"][metric]:
                    raise RuntimeError(f"versions differ in {metric}: {dataset}")
        summary = {}
        for label, raw in samples.items():
            summary[label] = dict(samples=raw, median_ms=statistics.median(s["read_ns"] for s in raw) / 1e6,
                min_ms=min(s["read_ns"] for s in raw) / 1e6, max_ms=max(s["read_ns"] for s in raw) / 1e6,
                max_peak_rss_bytes=max(s["peak_rss_bytes"] for s in raw))
        speedup = summary["baseline"]["median_ms"] / summary["optimized"]["median_ms"]
        results.append(dict(dataset=dataset, origin=[7, 11], extent=[side, side], cache_mode="on", versions=summary, speedup=speedup))
        print(f"{dataset}: {summary['baseline']['median_ms']:.3f} -> {summary['optimized']['median_ms']:.3f} ms ({speedup:.2f}x)", flush=True)
    report = dict(schema_version=1, timestamp=datetime.now(timezone.utc).isoformat(), platform=platform.platform(),
                  toolchain=subprocess.check_output(["moon", "version", "--all"], text=True),
                  baseline_commit=args.baseline_commit, optimized_commit=args.optimized_commit,
                  binaries={label: dict(path=str(path), sha256=hashlib.sha256(path.read_bytes()).hexdigest()) for label, path in binaries.items()},
                  trials=args.trials, discarded_trials=1, ordering="alternating baseline/optimized on each trial",
                  page_cache="not flushed; not cold disk", memory_metric="reader process OS high-water RSS / Windows peak working set",
                  datasets=inventory, results=results)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--optimized", type=Path, required=True)
    parser.add_argument("--baseline-commit", required=True)
    parser.add_argument("--optimized-commit", required=True)
    parser.add_argument("--work-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--trials", type=int, default=5)
    args = parser.parse_args()
    if not 1 <= args.trials <= 20: parser.error("trials must be 1..20")
    main(args)
