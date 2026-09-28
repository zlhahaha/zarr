# Zarr development handoff

This file records verified progress and the next implementation priorities. Update it after each meaningful change; `docs/ROADMAP.md` remains the detailed phase plan. Do not add the contest proposal here: it is kept outside this repository.

## Current baseline (2026-09-27)

- Module: `zlhahaha/zarr`, Apache-2.0. Version `0.2.0` with read-only Zarr v3 sharding-indexed support was published on Mooncakes on 2026-09-27; `moon view zlhahaha/zarr --versions` lists both `0.2.0` and `0.1.0`.
- Public API covers v2/v3 numeric and boolean arrays, element and rectangular-slice I/O, groups and attributes, memory/native filesystem stores, and native read-only HTTP regional hydration. Native `FileStore` can read v3 sharding-indexed arrays through the same typed API, but cannot write them. Memory and HTTP stores do not hydrate shards. See README's support matrix for exact boundaries.
- Compression: raw/gzip/zstd on v2/v3, zlib on v2, Blosc1 LZ4 read/write (no, byte or bit shuffle), and read-only Blosc1 LZ4HC/Zlib/Zstd. Unsupported metadata/codecs fail explicitly.
- Interoperability: 43 committed zarr-python 3.4.0 fixtures are read, including four sharding variants; reverse checks cover 32 MoonBit-written stores. CI covers Linux/macOS/Windows native and Linux wasm-gc, plus source packaging and Python interoperability on Linux.
- Last verified public release CI: commit [`c51c033`](https://github.com/zlhahaha/zarr/commit/c51c033a801582251951479c927dd5dde1cb8e0a), [run 36296920650](https://github.com/zlhahaha/zarr/actions/runs/36296920650), four matrix jobs successful (Linux/macOS/Windows native and Linux wasm-gc). The Linux native job validated the `0.2.0` source package and completed zarr-python reverse interoperability checks. The first feature run failed only because CI still named the old `0.1.0` archive; its artifact path was changed to a version-independent glob.
- `PROPOSAL.md` was removed from the current GitHub branch in `e1d575e`; its earlier versions remain in Git history. The local contest proposal outside this repository is not part of release packaging.

## Release implementation and verification

- Implemented v3 sharding-indexed layout parsing and native filesystem range reads. An element/region read fetches only the shard index (capped at 16 MiB) and selected encoded inner chunk (capped at 64 MiB), not the entire shard. Supports start/end indexes, little/big-endian index bytes, optional CRC32C, edge shards and absent inner chunks, then reuses the typed bytes/compression decoder. Sharded writes return `false`.
- Added four independent zarr-python 3.4.0 fixtures: 2D gzip with edge/absent chunks; start index with boundary shard; big-endian index/inner bytes without CRC; Blosc LZ4 inner chunks. Added CRC32C check-vector and malformed-index tests.
- Final local validation: native 85/85 and wasm-gc 49/49; native/wasm-gc checks and builds, `moon info`, `moon fmt --check`, `moon package --list`, and `git diff --check` passed. `moon publish` returned `200 OK`, and the registry version list confirms `0.2.0`.
- GitHub was initially synchronized through the connected GitHub API because this machine temporarily could not reach `github.com:443` for ordinary `git push`. Every uploaded blob SHA and remote tree SHA matched the local Git objects; refs were updated without force. Normal Git connectivity returned, so `git fetch` and a no-content merge (`ef00522`) reconciled the local and API-created histories; ordinary `git push` succeeded. Local `main` and `origin/main` are aligned again.
- README, usage guide, roadmap, changelog, and fixture inventory are published with the release. The off-repository contest proposal was updated locally but has not been submitted or added to GitHub.

## Acceptance documentation update (2026-09-28)

- README and usage guide now require `moonc >= 0.10.14` and explicitly install `moonbitlang/async@0.20.3` as a direct dependency when a consumer imports async packages. Cloned repository examples need only `moon update`, since `moon.mod` already declares it.
- The usage guide includes a complete standalone native quickstart: fresh project commands, executable `moon.pkg`, full `async fn main`, compressed multi-chunk region write/reopen/read assertions, successful-run temporary-store cleanup, and the expected output `Zarr quickstart: 100,200,300`. README validation commands explicitly select native/wasm-gc targets.
- Corrected error semantics: typed validation/decoder rejection returns `None`/`false`, missing chunks return fill values, and native filesystem errors can propagate. Added a complete `catch` helper and clarified that exceptions do not roll back partially completed region writes.
- Reproduction used a new independent consumer under ignored `_build/docs-repro-20260928/zarr-quickstart`, with published `zlhahaha/zarr@0.2.0` and direct async `0.20.3` dependencies, not the repository's local source. Initial dependency installation used the registry cache because sandboxed registry-index locking was unavailable; rerunning both installation commands with network/cache access refreshed the registry index successfully. Source/configuration were copied verbatim from the guide; native strict check, build and quickstart execution passed on `moonc v0.10.14+7d59c7ec9`.
- The guide's unchanged `catch` helper was compiled and exercised for successful metadata reads, an absent key (`None`), and reading a directory as a file (caught `OSError`). Native 85/85 and wasm-gc 49/49 repository tests, both target checks/builds, all three repository examples, `moon info`, `moon fmt`, and `moon fmt --check` passed.
- Documentation-only maintenance: no library API changes, new Mooncakes publication, or contest submission. Published `0.2.0` is immutable; these corrected documents belong to the repository until a future explicitly requested release.

## Priority queue

The P0 Blosc LZ4 write milestone and the first P1 sharding-indexed read milestone are complete and verified. Do not start the next priority until the user asks.

1. **P1 — Storage scale (await user instruction):** benchmark representative multi-chunk slices and peak memory. Improve chunk streaming/cache behavior where measurements show a bottleneck; avoid claiming bounded-memory whole-array reads until proved.
2. **P2 — Ecosystem fit (await user instruction):** evaluate an object-store adapter and ndarray interop without duplicating existing numeric-computation libraries; add only after store and typed-array boundaries are stable.
3. **P2 — Release maintenance (await user instruction):** maintain docs, metadata fuzz/property tests and future codec/format compatibility.

## Working rules

- Treat README support claims as test-backed, not aspirational. Run `moon info && moon fmt`, inspect `.mbti` diffs, then native/wasm checks and tests after code changes; verify Python interoperability and CI for codec/storage changes.
- Preserve unrelated work and generated `integration/.roundtrip/` stores. Fixture generators refuse to overwrite existing stores; use new fixture names or validated, recoverable moves for regeneration.
- Commit coherent features; push verified work to `main` under the user's prior authorization. Do not force-push or submit contest materials. A new Mooncakes version must be requested and verified before publication; `0.2.0` has already been published and cannot be overwritten.
