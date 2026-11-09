# Complete v3 shard writes

Since 0.10.0, native filesystem `uint8`, `uint16` and `float32` arrays can create and replace complete v3 `sharding_indexed` objects. This is useful for volume conversion, cropped data exports and preprocessing pipelines: many small independently compressed chunks share one filesystem object. Read the result with the existing typed region/tile APIs or zarr-python.

## Create and replace

Import `zlhahaha/zarr/store/fs` as `@fs`, `zlhahaha/zarr/codec` as `@codec`, and run inside `async fn main`. The project needs the direct `moonbitlang/async@0.20.3` dependency and `moonc >= 0.10.20`.

```moonbit
guard @fs.FileStore::new("output.zarr") is Some(store) else { abort("store") }
guard store.create_sharded_u8(
    "", [9], [2], [4], b'\x05', compression=@codec.Gzip(1),
  ) is Some(array) else { abort("new array required") }
guard array.write_shard([0], b"\x01\x02\x03\x04") else { abort("shard") }
guard array.write_shard([2], b"\x09") else { abort("edge shard") }
// Unwritten middle shard supplies four fill values.
guard array.read_region([0], [9]) == Some(b"\x01\x02\x03\x04\x05\x05\x05\x05\x09") else {
  abort("values")
}
```

Use a new output path on each run. The executable [interop generator](../cmd/shard_interop/main.mbt) and the [independent volume application](../examples/volume_pipeline/README.md) are complete runnable examples.

- `create_sharded_u8/u16/f32(path, shape, chunk_shape, shard_shape, fill, ...)` creates **v3** metadata and refuses an existing array/group. `chunk_shape` describes inner independently encoded chunks; each positive shard dimension must be an integer multiple of the matching chunk dimension.
- `write_shard(coordinates, values)` takes **outer shard coordinates**, not inner chunk coordinates or element coordinates. Supply exactly the clipped logical rectangle for that shard, flattened in C order. At an array edge, omit values outside the logical shape; the implementation pads edge inner chunks with fill and marks wholly outside chunks absent.
- Repeating a complete write replaces that single shard. It does not read or merge old contents, and can replace an old corrupt shard. Unwritten shards return fill values.
- Existing `write` and `write_region` still return `false` for sharded arrays, preserving their previous rejection behavior. Other dtypes, memory sharded typed writes and HTTP/S3 writes are not added by this release.
- Options include raw/gzip/zstd and the existing writable Blosc-LZ4 subset, start/end index, little/big-endian index and optional CRC32C. `u16/f32` also accept `big_endian` for inner data bytes, independently of index endian.

## Safety and memory

Validation, exact value count, `ReadLimits` region/chunk limits and the final encoded shard limit are checked before replacing an existing object. Each encoded shard including its index must fit `max_chunk_bytes` (64 MiB by default); the index is separately capped at 16 MiB by supported layout validation. Choose shards small enough for this implementation rather than assuming arbitrarily large Zarr objects are writable.

The implementation buffers encoded inner chunks, index and the final shard, in addition to input values and decoded scratch data. These byte/work limits are **not** a peak-memory bound or a streaming writer. The single-shard commit uses exclusive sibling staging, synchronized data and replacement rename from [WRITE_SAFETY.md](WRITE_SAFETY.md). Filesystem exceptions can propagate; catch them as in [USAGE.md](USAGE.md). A validation failure returns `false` and leaves the old shard untouched. A rename that already committed cannot be rolled back by later cancellation.

This is not a multi-shard transaction, directory transaction, partial-shard merge or concurrent-writer snapshot. Concurrent complete writers to the same key can replace each other's results; serialize them when that matters. Metadata creation and subsequent shards commit separately. On failure during a pipeline, the output can be incomplete.

For callers already holding encoded chunks, portable `shard.encode(layout, chunks, max_bytes=...)` packs C-index-order payloads (`None` denotes missing fill) without applying codecs. `shard.metadata_json` wraps supported ordinary v3 metadata in a validated sharding layout. These low-level functions do not provide typed store writes.

## Independent verification

```sh
python -m pip install zarr==3.4.0 numpy==2.5.3
moon run --target native cmd/shard_interop _build/shards-1
python scripts/verify_shard_roundtrip.py _build/shards-1
moon run --target native cmd/shard_interop _build/shards-1 verify
```

Choose another root for another run. Python checks every value in ten MoonBit-written stores: eight uint8 combinations of index location/endian/checksum, a big-endian uint16 Zstd 2D store and a float32 gzip 3D store. It then partially updates three stores; MoonBit reads those updates back. Regression tests additionally cover missing/edge/scalar/zero-extent arrays, complete replacement, damaged old objects, invalid input and budget rejection preserving old bytes. Source CI runs the reverse check on Linux, macOS and Windows native.
