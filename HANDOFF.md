# Zarr development handoff

This file records verified progress and the next implementation priorities. Update it after each meaningful change; `docs/ROADMAP.md` remains the detailed phase plan. Do not add the contest proposal here: it is kept outside this repository.

## Current baseline (2026-09-27)

- Module: `zlhahaha/zarr`, Apache-2.0. Version `0.1.0` was published on Mooncakes on 2026-09-25. Current source is being prepared as `0.2.0` with read-only Zarr v3 sharding-indexed support. Do not claim `0.2.0` is published until `moon view zlhahaha/zarr` confirms it.
- Public API covers v2/v3 numeric and boolean arrays, element and rectangular-slice I/O, groups and attributes, memory/native filesystem stores, and native read-only HTTP regional hydration. Native `FileStore` can read v3 sharding-indexed arrays through the same typed API, but cannot write them. Memory and HTTP stores do not hydrate shards. See README's support matrix for exact boundaries.
- Compression: raw/gzip/zstd on v2/v3, zlib on v2, Blosc1 LZ4 read/write (no, byte or bit shuffle), and read-only Blosc1 LZ4HC/Zlib/Zstd. Unsupported metadata/codecs fail explicitly.
- Interoperability: 43 committed zarr-python 3.4.0 fixtures are read, including four sharding variants; reverse checks cover 32 MoonBit-written stores. CI covers Linux/macOS/Windows native and Linux wasm-gc, plus source packaging and Python interoperability on Linux.
- Last verified public feature CI before this change: commit `72dfe13`, [run 36087401276](https://github.com/zlhahaha/zarr/actions/runs/36087401276), four matrix jobs successful (Linux/macOS/Windows native and Linux wasm-gc). The `0.2.0` feature is committed locally at `ab71872` but has not reached GitHub, so its public CI is pending.
- `PROPOSAL.md` was removed from the current GitHub branch in `e1d575e`; its earlier versions remain in Git history. The local contest proposal outside this repository is not part of release packaging.

## Latest verified local change

- Implemented v3 sharding-indexed layout parsing and native filesystem range reads. An element/region read fetches only the shard index (capped at 16 MiB) and selected encoded inner chunk (capped at 64 MiB), not the entire shard. Supports start/end indexes, little/big-endian index bytes, optional CRC32C, edge shards and absent inner chunks, then reuses the typed bytes/compression decoder. Sharded writes return `false`.
- Added four independent zarr-python 3.4.0 fixtures: 2D gzip with edge/absent chunks; start index with boundary shard; big-endian index/inner bytes without CRC; Blosc LZ4 inner chunks. Added CRC32C check-vector and malformed-index tests.
- Final local validation: native 85/85 and wasm-gc 49/49; native/wasm-gc checks and builds, `moon info`, `moon fmt --check`, `moon package --list`, and `git diff --check` pass. An elevated `moon publish --dry-run` received `202 Accepted` from Mooncakes for `0.2.0` with "No changes were made"; the CLI nevertheless exits 1 after printing that accepted response. No actual publication was attempted.
- Release hold: `git push origin main` failed twice because `github.com:443` is unreachable from this machine, including with elevated network permission. GitHub SSH port 22 is reachable but the current environment has no accepted public key. A GitHub connection was suggested in Codex but is not installed/confirmed. Keep the local commit and proposal; after connectivity is restored, push `main`, verify all GitHub CI jobs, then run `moon publish` for `0.2.0` and confirm with `moon view zlhahaha/zarr`. Do not publish while the repository still shows only `0.1.0` source.
- README, usage guide, roadmap, changelog, fixture inventory, and off-repository contest proposal have been updated. Release/CI verification remains pending.

## Priority queue

The P0 Blosc LZ4 write milestone is complete. The user authorized the first P1 feature and Mooncakes update in the present task.

1. **P1 — Zarr v3 sharding-indexed:** implementation, Python fixtures and local tests complete. Push is blocked by GitHub connectivity; then verify cross-platform CI and perform the authorized Mooncakes `0.2.0` update. Do not describe sharded writes, HTTP hydration or arbitrary codecs as implemented.
2. **P1 — Storage scale (await user instruction after this task):** benchmark representative multi-chunk slices and peak memory. Improve chunk streaming/cache behavior where measurements show a bottleneck; avoid claiming bounded-memory whole-array reads until proved.
3. **P2 — Ecosystem fit (await user instruction):** evaluate an object-store adapter and ndarray interop without duplicating existing numeric-computation libraries; add only after store and typed-array boundaries are stable.
4. **P2 — Release maintenance (await user instruction):** maintain docs, metadata fuzz/property tests and future codec/format compatibility.

## Working rules

- Treat README support claims as test-backed, not aspirational. Run `moon info && moon fmt`, inspect `.mbti` diffs, then native/wasm checks and tests after code changes; verify Python interoperability and CI for codec/storage changes.
- Preserve unrelated work and generated `integration/.roundtrip/` stores. Fixture generators refuse to overwrite existing stores; use new fixture names or validated, recoverable moves for regeneration.
- Commit coherent features; push verified work to `main` under the user's prior authorization. Do not force-push or submit contest materials. The user's present request authorizes updating Mooncakes, but verify CI and package contents before publishing an immutable version.
