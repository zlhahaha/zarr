# Zarr development handoff

This file records verified progress and the next implementation priorities. Update it after each meaningful change; `docs/ROADMAP.md` remains the detailed phase plan. Do not add the contest proposal here: it is kept outside this repository.

## Current baseline (2026-09-24)

- Module: `zlhahaha/zarr`, version `0.1.0`, Apache-2.0. This is an early source preview, **not** a Mooncakes publication. The user explicitly asked not to publish yet.
- Public API covers v2/v3 numeric and boolean arrays, element and rectangular-slice I/O, groups and attributes, memory/native filesystem stores, and native read-only HTTP regional hydration. See README's support matrix for exact boundaries.
- Compression: raw/gzip/zstd on v2/v3, zlib on v2, and a read-only Blosc1 subset (LZ4/LZ4HC/Zlib/Zstd with no, byte or bit shuffle). Unsupported metadata/codecs fail explicitly.
- Interoperability: 39 committed zarr-python 3.4.0 fixtures are read; zarr-python verifies 28 MoonBit-written stores. CI covers Linux/macOS/Windows native and Linux wasm-gc, plus source packaging and Python interoperability on Linux.
- Last verified public feature CI: commit `2570b0b`, [run 36016398630](https://github.com/zlhahaha/zarr/actions/runs/36016398630), four matrix jobs successful, including fresh Python reverse interoperability on Linux; the `zarr-0.1.0-source-package` artifact is present. Recheck newer CI before claiming it is current.
- `PROPOSAL.md` was removed from the current GitHub branch in `e1d575e`; its earlier versions remain in Git history. The local contest proposal outside this repository is not part of release packaging.

## Latest verified local change

- Added Blosc bitshuffle read support for v2 and v3 LZ4 frames, preserving the upstream rule that a short internal block with a non-multiple-of-eight element count is not transformed. Four zarr-python fixtures cover `uint16`, `float32`, and multiple internal blocks; the committed fixture inventory now totals 39 stores.
- Ran `moon info`, `moon fmt`, `moon fmt --check`, native and wasm-gc `moon check --deny-warn` and builds. Native tests: 74/74; wasm-gc tests: 42/42. No `.mbti` interface diff. The pushed feature commit passed all four GitHub CI jobs.
- `moon package --list` includes `HANDOFF.md` and the new codec source. A local rerun of the Python reverse verifier stopped at a missing pre-existing `integration/.roundtrip/v3_zstd_checksum_u8.zarr`; it reads generated stores from prior runs, and those were not overwritten or removed. CI regenerates all reverse fixtures in a clean checkout, so its result is the authoritative fresh reverse check for this change.

## Priority queue

1. **P0 — Common Blosc compatibility:** assess Blosc write support, especially the v2 default path and v3 BloscCodec; keep unsupported compressors explicit. Read-only bitshuffle is complete and CI-verified.
2. **P1 — Zarr v3 sharding-indexed:** implement and test shard index interpretation and bounded reads before claiming real-world large-dataset coverage. Add Python-generated fixtures, including edge shards and absent chunks.
3. **P1 — Storage scale:** benchmark representative multi-chunk slices and peak memory. Improve chunk streaming/cache behavior where measurements show a bottleneck; avoid claiming bounded-memory whole-array reads until proved.
4. **P2 — Ecosystem fit:** evaluate an object-store adapter and ndarray interop without duplicating existing numeric-computation libraries; add only after store and typed-array boundaries are stable.
5. **P2 — Release readiness:** maintain docs, malformed-input/property tests and cross-platform CI. Mooncakes publication remains held until the user explicitly authorizes it.

## Working rules

- Treat README support claims as test-backed, not aspirational. Run `moon info && moon fmt`, inspect `.mbti` diffs, then native/wasm checks and tests after code changes; verify Python interoperability and CI for codec/storage changes.
- Preserve unrelated work and generated `integration/.roundtrip/` stores. Fixture generators refuse to overwrite existing stores; use new fixture names or validated, recoverable moves for regeneration.
- Commit coherent features; push verified work to `main` under the user's prior authorization. Do not force-push, publish Mooncakes, or submit contest materials without explicit direction.
