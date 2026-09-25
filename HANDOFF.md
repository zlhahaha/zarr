# Zarr development handoff

This file records verified progress and the next implementation priorities. Update it after each meaningful change; `docs/ROADMAP.md` remains the detailed phase plan. Do not add the contest proposal here: it is kept outside this repository.

## Current baseline (2026-09-25)

- Module: `zlhahaha/zarr`, version `0.1.0`, Apache-2.0. This is an early source preview, **not** a Mooncakes publication. The user explicitly asked not to publish yet.
- Public API covers v2/v3 numeric and boolean arrays, element and rectangular-slice I/O, groups and attributes, memory/native filesystem stores, and native read-only HTTP regional hydration. See README's support matrix for exact boundaries.
- Compression: raw/gzip/zstd on v2/v3, zlib on v2, Blosc1 LZ4 read/write (no, byte or bit shuffle), and read-only Blosc1 LZ4HC/Zlib/Zstd. Unsupported metadata/codecs fail explicitly.
- Interoperability: 39 committed zarr-python 3.4.0 fixtures are read; reverse checks cover 32 MoonBit-written stores (28 existing plus four Blosc LZ4 stores). CI covers Linux/macOS/Windows native and Linux wasm-gc, plus source packaging and Python interoperability on Linux.
- Last verified public feature CI: commit `935dff6`, [run 36087208602](https://github.com/zlhahaha/zarr/actions/runs/36087208602), four matrix jobs successful (Linux/macOS/Windows native and Linux wasm-gc). The Linux native job ran fresh Python reverse interoperability, including the four new Blosc stores; the `zarr-0.1.0-source-package` artifact is present.
- `PROPOSAL.md` was removed from the current GitHub branch in `e1d575e`; its earlier versions remain in Git history. The local contest proposal outside this repository is not part of release packaging.

## Latest verified local change

- Added one-block Blosc1 LZ4 writing with no, byte or bit shuffle and a memcpy fallback. The v2/v3 metadata parser marks compatible LZ4 arrays writable; explicit nonzero `blocksize` or mismatched v3 `typesize` stays read-only. Other Blosc compressors remain read-only. Levels 1–9 currently share the same fast encoder; level 0 emits memcpy.
- Added two memory-array regression tests, two low-level codec tests and a native reverse-interoperability generator. zarr-python 3.4.0 read all four new stores: v2 byte-shuffle `uint16`, v3 bitshuffle/no-shuffle `uint16`, and a v2 short memcpy `uint8` frame. The verifier checks that the first three are actually compressed frames.
- Ran `moon info`, `moon fmt`, `moon fmt --check`, native and wasm-gc `moon check --deny-warn` and builds. Native tests: 78/78; wasm-gc tests: 46/46. `moon package --list` includes the new codec and generator. The feature commit passed all four public CI jobs, including fresh Python reverse checks.
- The full old reverse verifier cannot run against this local machine's stale ignored `integration/.roundtrip/` directory, which lacks an older generated store. The new Blosc verifier passed locally without touching old stores. Fresh GitHub CI regenerated and verified all reverse stores successfully.

## Priority queue

The P0 Blosc LZ4 write milestone is complete and verified. Do not start a new priority until the user asks.

1. **P1 — Zarr v3 sharding-indexed (await user instruction):** implement and test shard index interpretation and bounded reads before claiming real-world large-dataset coverage. Add Python-generated fixtures, including edge shards and absent chunks.
2. **P1 — Storage scale (await user instruction):** benchmark representative multi-chunk slices and peak memory. Improve chunk streaming/cache behavior where measurements show a bottleneck; avoid claiming bounded-memory whole-array reads until proved.
3. **P2 — Ecosystem fit (await user instruction):** evaluate an object-store adapter and ndarray interop without duplicating existing numeric-computation libraries; add only after store and typed-array boundaries are stable.
4. **P2 — Release readiness (await user instruction):** maintain docs, malformed-input/property tests and cross-platform CI. Mooncakes publication remains held until the user explicitly authorizes it.

## Working rules

- Treat README support claims as test-backed, not aspirational. Run `moon info && moon fmt`, inspect `.mbti` diffs, then native/wasm checks and tests after code changes; verify Python interoperability and CI for codec/storage changes.
- Preserve unrelated work and generated `integration/.roundtrip/` stores. Fixture generators refuse to overwrite existing stores; use new fixture names or validated, recoverable moves for regeneration.
- Commit coherent features; push verified work to `main` under the user's prior authorization. Do not force-push, publish Mooncakes, or submit contest materials without explicit direction.
