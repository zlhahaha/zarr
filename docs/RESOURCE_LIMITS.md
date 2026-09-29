# Read resource budgets

Since `0.4.0`, typed arrays use an immutable `store.ReadLimits` policy. These limits bound individual inputs, decoded chunks and requested work; **they are not a process-memory limit, transaction, timeout or streaming API**.

## Defaults and enforcement

| Setting | Default | Enforcement |
| --- | ---: | --- |
| `max_metadata_bytes` | 1048576 (1 MiB) | Native metadata/attributes/consolidated files before allocation; memory/HTTP metadata before UTF-8/JSON parsing |
| `max_chunk_bytes` | 67108864 (64 MiB) | Native ordinary object or selected shard payload before allocation; memory encoded chunks before decoding |
| `max_decoded_chunk_bytes` | 67108864 (64 MiB) | Declared chunk size before typed opening/fill allocation and before codec decoding |
| `max_region_bytes` | 67108864 (64 MiB) | Logical dtype bytes in a region, before chunk enumeration/result allocation |
| `max_region_elements` | 8388608 | Region element count, before enumeration/result allocation |
| `max_chunks` | 16384 | Touched chunk count computed without building a list |
| `max_rank` | 64 | Array rank at typed opening/region preflight |
| `max_json_depth` | 64 | Constant-space structural scan before JSON parsing; braces in quoted/escaped strings do not count |

All limits apply together. For example, `uint8` regions are limited to 8 MiB of logical data by the element cap, while `float64` regions can reach 64 MiB. Chunk bytes refer to the full regular/inner chunk, including fill at array edges, not only the requested overlap. The JSON scan is a nesting/size guard, not a replacement for UTF-8 or JSON syntax validation.

`ReadLimits::new(...)` returns `None` if **any** cap is zero or negative. Zero does not disable these protections. Explicitly raise positive caps for trusted workloads after considering memory use. Existing constructors and typed signatures still work with defaults, but formerly accepted oversized inputs can now be rejected; this is intentional hardening, not full legacy-behavior equivalence.

## Configure

Import `zlhahaha/zarr/store` as `@store` alongside your normal packages. A native filesystem consumer also imports `zlhahaha/zarr/store/fs` as `@fs`, and installs `moonbitlang/async@0.20.3` directly when using async packages. See [USAGE](USAGE.md#native-array-example) for a complete standalone project.

```moonbit
guard @store.ReadLimits::new(
  max_metadata_bytes=1048576,
  max_chunk_bytes=8388608,
  max_decoded_chunk_bytes=8388608,
  max_region_bytes=8388608,
  max_region_elements=1048576,
  max_chunks=4096,
  max_rank=8,
  max_json_depth=32,
) is Some(limits) else { return }
guard @fs.FileStore::new("data.zarr", read_limits=limits) is Some(files)
  else { return }
let memory = @store.MemoryStore::new(read_limits=limits)
```

`FileStore::open_consolidated` and `open_consolidated_v3` also accept `read_limits=limits`. Native temporary memory views inherit the filesystem policy, including explicit increases. `MemoryStore::read_limits()` and `FileStore::read_limits()` expose the policy for inspection/preflight; `allows_region` checks products and counts without enumeration.

`HttpStore::new(..., read_limits=limits, max_hydration_bytes=67108864)` applies the shared region/decode/metadata policy and caps the cumulative encoded chunk bytes retained in the returned store. Its existing `max_metadata_bytes`, `max_chunk_bytes` and `max_chunks` settings still apply; the stricter cap wins. HTTP defaults remain 1024 touched chunks and 64 MiB cumulative hydration. A candidate chunk is bounded per-object before checking whether it fits the remaining cumulative budget, so transient download/cache allocations are not included in `max_hydration_bytes`.

Native sharded reads still have an independent fixed 16 MiB index limit and 64 MiB selected encoded-payload limit. `ReadLimits.max_chunk_bytes` can further restrict the selected payload; it does not cap the entire physical shard size. Index cache settings and their zero-to-disable behavior are separate from these read budgets.

## Failure contract

- A native file/object exceeding its metadata/encoded input cap raises **`@fs.ReadLimitExceeded(key)`**. This includes the public `FileStore::get` and typed reads fetching that object. Catch it separately from OS errors; **it is never returned as a missing chunk/fill value**.
- Invalid/over-budget array rank, declared decoded chunk size, region work or JSON nesting returns `None` from typed opening/reads. In-memory encoded-chunk rejection and codec corruption also return `None`. A region budget rejection occurs before chunk I/O, enumeration and result allocation.
- Budget guards also apply to typed constructors and read-modify-write paths. Region writes exceeding the work policy return `false`; other native input failures can raise. Since `0.5.0`, individual filesystem keys use [safe replacement](WRITE_SAFETY.md), but multi-key/region writes remain non-atomic and previously written chunks are not rolled back.
- Absent objects and valid absent shard entries still return the declared fill value. Invalid bytes or a truncated compressed frame do not.
- Native reads open a handle, check that handle's size, and perform a fixed-length read rather than reading to EOF. Concurrent growth is not included; shrinkage/short reads can raise I/O exceptions. Files must remain stable during operations; no concurrent-writer snapshot is provided.
- Raw `MemoryStore::put/get` are caller-managed map operations and do not enforce these caps or bound total stored bytes. Direct low-level metadata parsers/codecs also do not automatically inherit a store policy. Use typed/store openers, or explicitly preflight low-level inputs.

## Reproduce the checks

From the source checkout:

```sh
moon update
moon run --target native cmd/budget_demo
moon test --target native --deny-warn
moon test --target wasm-gc --deny-warn
```

The demo prints:

```text
Zarr budgets: valid read passed; region and encoded chunk rejected
```

It creates and cleans up its own temporary store, checks a normal read, rejects an oversized region and catches an oversized encoded chunk. Native CI executes it on Linux/macOS/Windows. Regression tests cover inclusive boundaries, invalid policies, signed/unsigned/boolean/float wrappers, huge valid selections, scalar/empty regions, deep/escaped JSON, declared oversized chunks, truncated writable-codec frames, gzip expansion, missing-fill distinctions, consolidated metadata, shard payload rejection before payload I/O, and HTTP work/cumulative-byte rejection. Small artificial caps exercise rejection without creating giant files or allocating giant outputs.

These are regression tests, not an exhaustive fuzzer or a security certification. No CPU deadline, aggregate concurrent-operation RAM limit, filesystem sandbox, symlink protection, whole-store memory cap or whole-array streaming guarantee is claimed. Result buffers, dtype conversion arrays, decoder internals, index/cache overhead and concurrent calls can consume more memory than the logical budgets. See [BENCHMARKS](BENCHMARKS.md) for measured OS peak memory and its separate limits.
