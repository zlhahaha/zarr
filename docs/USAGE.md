# Using Zarr from MoonBit

This library is an early Mooncakes release. Requires a MoonBit toolchain with **`moonc >= 0.10.14`**; inspect it with `moon version --all`. Filesystem and HTTP packages require the native backend. Add the published module to an existing MoonBit project:

```sh
moon add zlhahaha/zarr@0.5.0
```

For native examples importing `moonbitlang/async` or `moonbitlang/async/fs`, add a direct dependency as well:

```sh
moon add moonbitlang/async@0.20.3
```

A transitive dependency is not enough for your own package imports. Pure in-memory examples without `async` imports need only `zarr`. Alternatively, clone `https://github.com/zlhahaha/zarr` and run `moon update`; the repository already declares both dependencies.

## Packages

| Package | Purpose |
| --- | --- |
| `zlhahaha/zarr/metadata` | v2/v3 formats and parsed metadata |
| `zlhahaha/zarr/store` | In-memory encoded-byte store and shared `ReadLimits` policy |
| `zlhahaha/zarr/store/fs` | Native filesystem store and typed arrays |
| `zlhahaha/zarr/store/http` | Native-only HTTP read-only regional hydration |
| `zlhahaha/zarr/array` | In-memory typed arrays and creation helpers |
| `zlhahaha/zarr/codec` | Compression choices (`Raw`, `Gzip`, `Zlib`, `Zstd`, `BloscLz4`) |
| `zlhahaha/zarr/shard` | Internal v3 sharding layout and index validation used by the native filesystem adapter |
| `zlhahaha/zarr/hierarchy` | In-memory group and attribute operations |

The repository contains four runnable usage examples: `moon run --target wasm-gc cmd/main` for a portable in-memory v3 array, `moon run --target native cmd/native_demo` for zstd-compressed v3 creation and replacement of existing chunks, `moon run --target native cmd/v2_demo` for a gzip-compressed big-endian v2 array, and `moon run --target native cmd/budget_demo` for resource-budget rejection and recovery. The native examples create and remove their own temporary stores after a successful run. Each example exits unsuccessfully if a check fails.

## Native array example

To reproduce this example independently of the repository, create a new project and install the published dependencies:

```sh
moon new --user example zarr-quickstart
cd zarr-quickstart
moon add zlhahaha/zarr@0.4.0
moon add moonbitlang/async@0.20.3
```

On Windows, `moon new` may warn that it could not create the generated README symlink when Developer Mode is disabled. The project is still created; this example does not depend on that symlink.

Create a `native_demo` directory in that project and save the following as `native_demo/moon.pkg`:

```text
import {
  "zlhahaha/zarr/metadata",
  "zlhahaha/zarr/codec",
  "zlhahaha/zarr/store/fs",
  "moonbitlang/async/fs" @async_fs,
  "moonbitlang/async",
}

pkgtype(kind: "executable")

supported_targets = "native"
```

Save this complete program as `native_demo/main.mbt`. It creates a temporary v3 zstd-compressed array, writes a rectangle, reopens the store, checks the values and cleans up after a successful run:

```moonbit
///|
async fn main {
  let dir = @async_fs.tmpdir(prefix="zarr-quickstart")
  guard @fs.FileStore::new(dir) is Some(store) else {
    abort("invalid store path")
  }
  if !store.create_group_tree(@metadata.V3, "") {
    abort("root group creation failed")
  }
  guard store.create_u16(
      @metadata.V3, "pixels", [2, 3], [2, 2], (0 : UInt16),
      compression=@codec.Zstd(3),
    ) is Some(pixels) else {
    abort("array creation failed")
  }
  if !pixels.write_region(
      [0, 0], [1, 3],
      [(100 : UInt16), (200 : UInt16), (300 : UInt16)],
    ) {
    abort("region write failed")
  }
  guard @fs.FileStore::new(dir) is Some(reopened) else {
    abort("invalid store path")
  }
  guard reopened.open_u16("pixels") is Some(saved) else {
    abort("reopen failed")
  }
  guard saved.read_region([0, 0], [1, 3]) is Some(values) else {
    abort("region read failed")
  }
  if values != [(100 : UInt16), (200 : UInt16), (300 : UInt16)] {
    abort("unexpected values")
  }
  println("Zarr quickstart: \{values[0]},\{values[1]},\{values[2]}")
  @async_fs.rmdir(dir, recursive=true)
}
```

Run the commands below from the new project's root (the first two should succeed without warnings):

```sh
moon check --target native --deny-warn
moon build --target native
moon run --target native native_demo
```

Expected program output:

```text
Zarr quickstart: 100,200,300
```

This example intentionally lets unexpected filesystem exceptions fail the program, so it cannot silently report success after an I/O failure. For application-level recovery, see [Error handling](#error-handling).

`create_bool`, `create_u8`, `create_i8`, `create_u16`, `create_i16`, `create_u32`, `create_i32`, `create_u64`, `create_i64`, `create_f32`, and `create_f64` exist on `FileStore`; matching functions accept a `MemoryStore` in the `array` package. `int8` values use `Int` parameters/results and reject writes outside `-128..127`. Create a root group before adding named arrays so other Zarr readers can traverse the hierarchy. For deeper paths, `store.create_group_tree(@metadata.V3, "science/run")` creates missing ancestors without overwriting existing groups; use `@hierarchy.create_group_tree` with a `MemoryStore`. Omit `compression` for raw chunks. `Gzip(level)` works with v2/v3, `Zlib(level)` with v2 only, and `Zstd(level)` with v2/v3. For Blosc1 LZ4, use `BloscLz4(clevel, shuffle, typesize)`, e.g. `BloscLz4(5, 2, 2)` for `uint16` with bitshuffle. `shuffle` is 0 (none), 1 (byte) or 2 (bit); `typesize` must match the dtype's byte width. Level 0 writes a memcpy frame. Levels 1–9 currently use the same fast LZ4 encoder, so the requested level is retained in metadata but does not tune compression ratio. For v3 Zstd frames with a checksum, use `ZstdChecksum(level)`; it is rejected for v2. When metadata requires a checksum, reads also require the frame's checksum flag and reject corrupted payloads. `big_endian=true` is available for multi-byte types. The same typed API opens existing arrays with `store.open_u16("pixels")` and supports `read`, `write`, `read_region`, and `write_region`.

The first argument to region operations is the zero-based origin, the second is the extent. Values are in C order regardless of a v2 array's on-disk C/F chunk order. A missing chunk reads as the declared fill value; writing creates a full-sized chunk, including at array edges.

For a Zarr v2 hierarchy with `.zmetadata`, `FileStore::open_consolidated("data.zarr")` returns a read-only snapshot. This index is a zarr-python convention, not part of the v2 core storage specification. Its array and group metadata and attributes come exclusively from the consolidated index, while chunks still come from the filesystem. It can read hierarchies even when individual `.zarray`, `.zgroup`, and `.zattrs` files are absent. Writes through this view return `false`; reopen it after the index changes. Use `FileStore::new` for ordinary mutable stores.

For a Zarr v3 hierarchy with zarr-python's inline `consolidated_metadata` field in the root `zarr.json`, use `FileStore::open_consolidated_v3("data.zarr")`. This is likewise a native-only read-only snapshot: child `zarr.json` documents come from the root index, chunk bytes come from the filesystem, and changes to the index require reopening. It accepts the `kind="inline", must_understand=false` convention and does not write or update consolidated metadata. This v3 convention remains experimental in zarr-python.

For an existing v3 sharding-indexed array, use the same native typed opener, e.g. `store.open_u16("pixels")`, then `read` or `read_region`. The filesystem adapter locates the outer shard, reads at most 16 MiB of index data, validates its offsets and optional CRC32C, and reads only each selected encoded inner chunk (at most 64 MiB); it does not load a whole shard for a small selection. Indexes at the beginning or end of a shard, little- or big-endian index bytes, and supported inner bytes plus gzip/zstd/Blosc codecs are accepted. Missing shards and valid absent inner chunks return the declared fill value. Sharded arrays are **read-only**: `write` and `write_region` return `false`. `MemoryStore`, `HttpStore` hydration, and sharded array creation/writes are not implemented. This feature is tested against four zarr-python 3.4.0 fixtures, including edge shards and absent chunks.

Since `0.3.0`, each native typed `read_region` has its own bounded FIFO shard-index cache (16 MiB of index payload / 64 entries by default). Retained indexes have their length and optional CRC32C checked once; every selected entry still has bounds validated. No index or file handle persists across calls. Configure `FileStore::new("data.zarr", shard_index_cache_bytes=1048576, shard_index_cache_entries=16)`, or set either cap to zero to disable it; negative caps return `None`. An index larger than the cap is not retained, and eviction can cause re-reads. Consolidated snapshot openers use the defaults. Files must remain stable during a region read: this is not a concurrent-writer snapshot, and unchanged-size edits during that call are not detected.

`store.shard_read_stats()` reports cumulative successful index/payload range reads and bytes, cache hits, and peak retained index bytes; `store.reset_shard_read_stats()` resets the counters. They measure library calls, not physical disk traffic or total memory. Independent concurrent reads have independent cache caps. See [BENCHMARKS.md](BENCHMARKS.md) for executable comparisons, OS peak-memory measurements and performance limits.

For a static HTTP-served v2 or v3 hierarchy, the native-only `store/http` package can fetch just the metadata and chunks touched by a rectangle:

```moonbit
guard @http.HttpStore::new("https://example.org/data.zarr") is Some(remote) else { return }
guard remote.hydrate_region("science/image", [10, 20], [1, 3]) is Some(cache) else { return }
guard @array.open_u8(cache, "science/image") is Some(image) else { return }
let values = image.read_region([10, 20], [1, 3])
```

Import `zlhahaha/zarr/store/http` as `@http` and `zlhahaha/zarr/array` as `@array`. Hydration is read-only and returns a `MemoryStore`; changing it does not update the remote store. A 404 chunk is treated as the declared fill value, while non-200 responses and transport errors fail. The default caps are 1 MiB per metadata document, 64 MiB per encoded chunk and 1024 chunks per call; `HttpStore::new` accepts `max_metadata_bytes`, `max_chunk_bytes`, and `max_chunks` overrides. Successful metadata and chunk responses are cached on the `HttpStore` instance with 64 MiB and 4096-entry in-memory LRU limits by default; set `max_cache_bytes=0` to disable it, or tune `max_cache_bytes` and `max_cache_entries`. Missing and empty responses are not cached. Recreate the `HttpStore` to see remote changes. This is not yet an HTTP-backed typed array or a disk-persistent cache.

## Supported format subset

Both formats support regular chunk grids, safe logical paths, groups and attributes, boolean arrays and the ten numeric types above. v2 supports `.`/`/` chunk separators and C/F chunk order; v3 supports default and v2-compatible chunk keys plus the bytes serializer. Raw, gzip and zstd chunks are supported in both formats; zlib is supported in v2. A Blosc1 subset handles LZ4/LZ4HC, Zlib and Zstd frames with no shuffle, byte shuffle or bit shuffle, including incompressible memcpy frames and multiple internal blocks. LZ4 arrays can be created, opened and written with one-block Blosc1 frames; LZ4HC, Zlib and Zstd remain read-only. BloscLZ and Snappy are unsupported. Native filesystem reads also support the documented subset of v3 sharding-indexed; writes do not. Unsupported filters, storage transformers and codec chains are rejected rather than silently decoded incorrectly. Full-range `int64`/`uint64` fill values are preserved as exact JSON integers rather than rounded through floating point.

Large reads and writes still buffer the requested region. A `FileStore` uses native async filesystem APIs and is not available on wasm-gc; `MemoryStore` works on the tested native and wasm-gc targets. See [Error handling](#error-handling) for return values, exceptions and non-atomic writes.

## Resource budgets

Version `0.4.0` adds `@store.ReadLimits::new(...)` (import `zlhahaha/zarr/store`) and the optional `read_limits=limits` constructor argument for memory/filesystem/HTTP stores and consolidated openers. Defaults are 1 MiB metadata, 64 MiB encoded/decoded chunks, 64 MiB logical region bytes, 8388608 elements, 16384 touched chunks, rank 64 and JSON nesting 64. All limits are checked together; zero/negative policy caps are invalid, not an opt-out. Native temporary memory views inherit custom policies.

Oversized native metadata/encoded inputs raise `@fs.ReadLimitExceeded(key)` before allocating that input buffer. Region, declared decoded-size and JSON-depth rejection returns `None` from typed opening/reads; it is not a missing chunk. HTTP returns `None` and additionally defaults to 64 MiB cumulative encoded hydration (`max_hydration_bytes`). These controls are not a bound on total process memory; result buffers and conversions still allocate. Raw in-memory map and direct parser/codec calls remain caller-managed. See [RESOURCE_LIMITS.md](RESOURCE_LIMITS.md) for every setting, constructor example, native `catch` behavior and a runnable demo.

Zstd decoding first checks the dependency's conservative frame-size bound against the declared uncompressed chunk length. Consequently, a valid frame without known content size may be rejected. Full Blosc support, sharded writes/HTTP hydration, consolidated-metadata writes, HTTP write access, cloud object-store adapters, additional dtypes, and general ndarray arithmetic are not implemented yet. See [ROADMAP.md](ROADMAP.md) and the [support table](../README.md#status).

For floating-point arrays, `"NaN"`, `"Infinity"`, and `"-Infinity"` metadata fill values are accepted in both formats. Array creation serializes a NaN fill as the canonical `"NaN"` string. Hexadecimal NaN payload encodings from the v3 data-type specification are not yet supported.

## Error handling

Typed creation, opening, reading and writing operations return `None` or `false` when their validation or decoding rejects invalid metadata, unsupported encodings, out-of-bounds coordinates, or corrupt chunk data. Read-only views reject writes with `false`. Missing chunks (including valid absent inner chunks in a shard) are normal: typed reads return the declared fill value.

This is **not** a blanket I/O-error convention. `FileStore::get` returns `None` for an absent or invalid key, but other filesystem errors can propagate as exceptions. Native creation, opening, reading, writing and cleanup can also propagate filesystem exceptions, for example permission errors, reading a directory as a file, or an interrupted/truncated file read. Handle these separately from `None`/`false`; an uncaught exception fails the program. `HttpStore::hydrate_region`, in contrast, converts failed HTTP responses and transport errors to `None` (a 404 chunk still means a fill value).

For example, this complete helper uses the native package imports above and distinguishes a returned `None` from an exception. Add it to `native_demo/main.mbt` and call `print_metadata(reopened)` before cleanup to inspect the created metadata:

```moonbit
///|
async fn print_metadata(store : @fs.FileStore) -> Unit {
  let document = store.get("pixels/zarr.json") catch {
    error => {
      println("Filesystem I/O error: \{error}")
      return
    }
  }
  match document {
    Some(bytes) => println("Metadata bytes: \{bytes.length()}")
    None => println("Metadata key absent or invalid")
  }
}
```

The helper logs and handles an exception locally; it does not change the library's error contract. Wrap typed calls in `catch` similarly when your application needs recovery, or leave exceptions to propagate when the operation must fail.

Since `0.5.0`, individual native keys are written through an exclusively created sibling temporary file, a complete data-synchronized write, handle closure and same-directory replacement rename. Failure before replacement does not truncate the destination. Cooperative cancellation cleans up staging; cancellation during protected replacement can still result in a committed key. If cleanup itself fails, `fs.WriteCleanupFailed(temporary_path, diagnostic)` supersedes the original error and identifies the leftover file. See [WRITE_SAFETY.md](WRITE_SAFETY.md) for recovery guidance and the full failure contract.

A region write spanning multiple chunks is still **not atomic**: if a later chunk returns `false` or raises an exception, earlier chunks may already be saved. Catching an exception does not roll back those writes. This also applies to multi-key metadata/group creation. Individual replacement is not a lock, snapshot or crash-durability promise. Temporary-store cleanup can itself fail and is another filesystem operation to handle when needed.
