# Compatibility and private-service maintenance

The 0.9.0 source gate expands to **157 native / 78 wasm-gc tests**, typed pull-reader lifecycle/remote tests and automatic signed sharded scans against real MinIO (25 actual Range responses in the recorded Windows run). Hash-pinned real-data statistics and RSS reproduction are in [REAL_DATA_BENCHMARK.md](REAL_DATA_BENCHMARK.md). Until the release/consumer acknowledgement is recorded, the independent registry fixture below remains on the already published 0.8.0.

Version **0.8.0** combines current-toolchain maintenance with hierarchy discovery and structured remote diagnostics. The earlier 0.7.1 preparation was incorporated without a separate release. Publication is verified using an independent registry consumer; prior immutable versions remain available.

## Current stable toolchain

On 2026-11-06, the official stable archives supplied `moon 0.1.20261104` and `moonc v0.10.20+65efd5b93` (2026-11-05). Source migrated deprecated derive syntax and the random constructor; the current formatter uses `Int32` for the existing 32-bit integer APIs. Source builds require 0.10.20. Native and wasm-gc check/build/test and executable examples are regression gates; published 0.7.0 retains its documented 0.10.14 baseline.

`moonbitlang/async@0.20.3` is intentionally pinned. It shields cancellation at runtime but predates the new compiler's `nocancel` effect annotation. The already-shielded write-cleanup function has a local `cancellable_defer` warning exception with an explanatory comment; budget-example/test cleanup is now explicitly shielded with similarly local exceptions. Project-wide `--deny-warn` stays enabled and the existing cancellation/write-safety tests remain active. Migrating to the newer standard-library async runtime is separate work because its cancellation model differs.

## Independent published-package consumer

`scripts/published_consumer/moon.mod` is a separate module pinned to **registry `zlhahaha/zarr@0.8.0`**, not a path override to this checkout. Its JSON report records the verified version. The pre-release compatibility fixture also checked 0.7.0; the current consumer downloaded and verified 0.8.0 after publication. It directly declares `moonbitlang/async`, as required by the usage guide. From the repository root with the desired MoonBit toolchain active:

```sh
python -m pip install zarr==3.4.0 numpy==2.5.3
python scripts/verify_published_consumer.py --output _build/published-consumer.json
```

The runner performs strict native checking, building and execution, verifies the installed dependency manifest, writes two independent 3D v2/gzip and v3/zstd stores, reopens and verifies every value and missing fill, then independently checks all values/chunks/compression using Python. The 0.8.0 consumer additionally validates node descriptors, traversal/budget errors and S3 result APIs without external network I/O, and Python independently opens its group hierarchy. Temporary output is removed after verification. CI runs this consumer on all three native platforms. The fixture's source is test-only and excluded from the library source archive.

## Real private MinIO reads

The fixed upstream server, disposable credentials, exact cases, commands and scope are documented in [REMOTE.md](REMOTE.md#reproduce-private-minio-integration). The expanded suite validates real signed pagination and Unicode discovery as well as ordinary/sharded reads. The 0.8.0 source has **142 native tests and 70 wasm-gc tests**. The existing 51 Python read fixtures and 40 reverse stores remain independent format gates. Production AWS, STS/role authorization, TLS deployment and remote writes remain outside these verified results.
