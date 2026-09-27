# Zarr development handoff

This file records verified progress and the next implementation priorities. Update it after each meaningful change; `docs/ROADMAP.md` remains the detailed phase plan. Do not add the contest proposal here: it is kept outside this repository.

## Current baseline (2026-09-27)

- Module: `zlhahaha/zarr`, Apache-2.0. Version `0.2.0` with read-only Zarr v3 sharding-indexed support was published on Mooncakes on 2026-09-27; `moon view zlhahaha/zarr --versions` lists both `0.2.0` and `0.1.0`.
- Public API covers v2/v3 numeric and boolean arrays, element and rectangular-slice I/O, groups and attributes, memory/native filesystem stores, and native read-only HTTP regional hydration. Native `FileStore` can read v3 sharding-indexed arrays through the same typed API, but cannot write them. Memory and HTTP stores do not hydrate shards. See README's support matrix for exact boundaries.
- Compression: raw/gzip/zstd on v2/v3, zlib on v2, Blosc1 LZ4 read/write (no, byte or bit shuffle), and read-only Blosc1 LZ4HC/Zlib/Zstd. Unsupported metadata/codecs fail explicitly.
- Interoperability: 43 committed zarr-python 3.4.0 fixtures are read, including four sharding variants; reverse checks cover 32 MoonBit-written stores. CI covers Linux/macOS/Windows native and Linux wasm-gc, plus source packaging and Python interoperability on Linux.
- Last verified public release CI: commit [`c51c033`](https://github.com/zlhahaha/zarr/commit/c51c033a801582251951479c927dd5dde1cb8e0a), [run 36296920650](https://github.com/zlhahaha/zarr/actions/runs/36296920650), four matrix jobs successful (Linux/macOS/Windows native and Linux wasm-gc). The Linux native job validated the `0.2.0` source package and completed zarr-python reverse interoperability checks. The first feature run failed only because CI still named the old `0.1.0` archive; its artifact path was changed to a version-independent glob.
- `PROPOSAL.md` was removed from the current GitHub branch in `e1d575e`; its earlier versions remain in Git history. The local contest proposal outside this repository is not part of release packaging.

## Latest verified local change

- Implemented v3 sharding-indexed layout parsing and native filesystem range reads. An element/region read fetches only the shard index (capped at 16 MiB) and selected encoded inner chunk (capped at 64 MiB), not the entire shard. Supports start/end indexes, little/big-endian index bytes, optional CRC32C, edge shards and absent inner chunks, then reuses the typed bytes/compression decoder. Sharded writes return `false`.
- Added four independent zarr-python 3.4.0 fixtures: 2D gzip with edge/absent chunks; start index with boundary shard; big-endian index/inner bytes without CRC; Blosc LZ4 inner chunks. Added CRC32C check-vector and malformed-index tests.
- Final local validation: native 85/85 and wasm-gc 49/49; native/wasm-gc checks and builds, `moon info`, `moon fmt --check`, `moon package --list`, and `git diff --check` passed. `moon publish` returned `200 OK`, and the registry version list confirms `0.2.0`.
- GitHub was synchronized through the connected GitHub API because this machine could not reach `github.com:443` for ordinary `git push`. Every uploaded blob SHA and remote tree SHA was checked against the local Git object; remote refs were updated without force. The local and remote `main` trees match, but their commit SHAs differ because the API created new commits. Do **not** force-push the local branch. Once ordinary Git HTTPS works, fetch and reconcile history before the next source push.
- README, usage guide, roadmap, changelog, and fixture inventory are published with the release. The off-repository contest proposal was updated locally but has not been submitted or added to GitHub.

## Priority queue

The P0 Blosc LZ4 write milestone and the first P1 sharding-indexed read milestone are complete and verified. Do not start the next priority until the user asks.

1. **P1 — Storage scale (await user instruction):** benchmark representative multi-chunk slices and peak memory. Improve chunk streaming/cache behavior where measurements show a bottleneck; avoid claiming bounded-memory whole-array reads until proved.
2. **P2 — Ecosystem fit (await user instruction):** evaluate an object-store adapter and ndarray interop without duplicating existing numeric-computation libraries; add only after store and typed-array boundaries are stable.
3. **P2 — Release maintenance (await user instruction):** maintain docs, metadata fuzz/property tests and future codec/format compatibility. Before new source pushes, resolve the local/remote commit-history divergence described above.

## Working rules

- Treat README support claims as test-backed, not aspirational. Run `moon info && moon fmt`, inspect `.mbti` diffs, then native/wasm checks and tests after code changes; verify Python interoperability and CI for codec/storage changes.
- Preserve unrelated work and generated `integration/.roundtrip/` stores. Fixture generators refuse to overwrite existing stores; use new fixture names or validated, recoverable moves for regeneration.
- Commit coherent features; push verified work to `main` under the user's prior authorization. Do not force-push or submit contest materials. A new Mooncakes version must be requested and verified before publication; `0.2.0` has already been published and cannot be overwritten.
