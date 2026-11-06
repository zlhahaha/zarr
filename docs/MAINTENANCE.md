# Compatibility and private-service maintenance

The repository prepares **0.7.1 (unreleased)**. Mooncakes **0.7.0 remains the latest published release**; this maintenance task does not publish or overwrite a registry version.

## Current stable toolchain

On 2026-11-06, the official stable archives supplied `moon 0.1.20261104` and `moonc v0.10.20+65efd5b93` (2026-11-05). Source migrated deprecated derive syntax and the random constructor; the current formatter uses `Int32` for the existing 32-bit integer APIs. Source builds require 0.10.20. Native and wasm-gc check/build/test and executable examples are regression gates; published 0.7.0 retains its documented 0.10.14 baseline.

`moonbitlang/async@0.20.3` is intentionally pinned. It shields cancellation at runtime but predates the new compiler's `nocancel` effect annotation. The already-shielded write-cleanup function has a local `cancellable_defer` warning exception with an explanatory comment; budget-example/test cleanup is now explicitly shielded with similarly local exceptions. Project-wide `--deny-warn` stays enabled and the existing cancellation/write-safety tests remain active. Migrating to the newer standard-library async runtime is separate work because its cancellation model differs.

## Independent published-package consumer

`scripts/published_consumer/moon.mod` is a separate module that depends on **registry `zlhahaha/zarr@0.7.0`**, not a path override to this checkout. It directly declares `moonbitlang/async`, as required by the usage guide. From the repository root with the desired MoonBit toolchain active:

```sh
python -m pip install zarr==3.4.0 numpy==2.5.3
python scripts/verify_published_consumer.py --output _build/published-consumer.json
```

The runner performs strict native checking, building and execution, verifies the installed dependency manifest, writes two independent 3D v2/gzip and v3/zstd stores, reopens and verifies every value and missing fill, then independently checks all values/chunks/compression using Python. Temporary output is removed after verification. CI runs this consumer on all three native platforms. The fixture's source is test-only and excluded from the library source archive.

## Real private MinIO reads

The fixed upstream server, disposable credentials, exact cases, commands and scope are documented in [REMOTE.md](REMOTE.md#reproduce-private-minio-integration). On Windows, the source passed **133 native tests and 67 wasm-gc tests**, the registry consumer and real MinIO suite. Existing Python fixtures and reverse interop remain independent correctness gates; the source migration does not add a new codec or broaden unsupported format claims. Production AWS, STS/role authorization, TLS deployment and remote writes remain outside these verified results.
