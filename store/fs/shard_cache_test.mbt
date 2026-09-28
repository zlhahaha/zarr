///|
async test "operation-local index cache reduces reads without changing values" {
  let path = "integration/fixtures/zarr-python/v3_shard_end_gzip_u16.zarr"
  guard @fs.FileStore::new(path) is Some(cached) else { fail("store") }
  guard @fs.FileStore::new(path, shard_index_cache_bytes=0) is Some(uncached) else {
    fail("uncached store")
  }
  guard cached.open_u16("") is Some(a) else { fail("array") }
  guard uncached.open_u16("") is Some(b) else { fail("array") }
  let expected = b.read_region([0, 0], [5, 7])
  assert_true(expected is Some(_))
  assert_eq(a.read_region([0, 0], [5, 7]), expected)
  let stats = cached.shard_read_stats()
  let baseline = uncached.shard_read_stats()
  assert_eq(stats.index_reads, 2)
  assert_eq(stats.index_cache_hits, 6)
  assert_eq(baseline.index_reads, 8)
  assert_eq(baseline.index_cache_hits, 0)
  assert_eq(stats.payload_bytes, baseline.payload_bytes)
  assert_eq(stats.payload_reads, baseline.payload_reads)
  assert_eq(stats.peak_cached_index_bytes, 136)
  assert_eq(baseline.peak_cached_index_bytes, 0)
  assert_eq(a.read_region([0, 0], [5, 7]), expected)
  assert_eq(cached.shard_read_stats().index_reads, 4)
  cached.reset_shard_read_stats()
  assert_eq(cached.shard_read_stats().index_reads, 0)
}

///|
async test "index cache byte and entry caps preserve reads" {
  let path = "integration/fixtures/zarr-python/v3_shard_end_gzip_u16.zarr"
  guard @fs.FileStore::new(path, shard_index_cache_bytes=67) is Some(tiny) else {
    fail("tiny cache")
  }
  guard tiny.open_u16("") is Some(a) else { fail("array") }
  assert_true(a.read_region([0, 0], [5, 7]) is Some(_))
  assert_eq(tiny.shard_read_stats().index_reads, 8)
  assert_eq(tiny.shard_read_stats().peak_cached_index_bytes, 0)
  guard @fs.FileStore::new(path, shard_index_cache_entries=1) is Some(one) else {
    fail("single entry")
  }
  guard one.open_u16("") is Some(b) else { fail("array") }
  assert_eq(b.read_region([0, 0], [5, 7]), a.read_region([0, 0], [5, 7]))
  assert_eq(one.shard_read_stats().peak_cached_index_bytes, 68)
  assert_true(one.shard_read_stats().index_reads > 2)
  assert_true(@fs.FileStore::new(path, shard_index_cache_bytes=-1) is None)
  assert_true(@fs.FileStore::new(path, shard_index_cache_entries=-1) is None)
  guard @fs.FileStore::new(path, shard_index_cache_entries=0) is Some(disabled) else {
    fail("disabled cache")
  }
  guard disabled.open_u16("") is Some(c) else { fail("array") }
  assert_eq(c.read_region([0, 0], [5, 7]), a.read_region([0, 0], [5, 7]))
  assert_eq(disabled.shard_read_stats().index_cache_hits, 0)
}

///|
async test "cache does not retain corrupted or changed indexes between reads" {
  let dir = @async_fs.tmpdir(prefix="zarr-shard-cache-test")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("temp store") }
  guard @fs.FileStore::new(
      "integration/fixtures/zarr-python/v3_shard_end_gzip_u16.zarr",
    )
    is Some(source) else {
    fail("fixture")
  }
  guard source.get("zarr.json") is Some(metadata) else { fail("metadata") }
  guard source.get("c/0/0") is Some(shard) else { fail("shard") }
  assert_true(store.put("zarr.json", metadata))
  assert_true(store.put("c/0/0", shard))
  guard store.open_u16("") is Some(array) else { fail("array") }
  let expected = array.read_region([0, 0], [4, 4])
  assert_true(expected is Some(_))
  let corrupt = shard.to_array()
  let last = corrupt.length() - 1
  corrupt[last] = (corrupt[last].to_uint() ^ 1U).to_byte()
  assert_true(store.put("c/0/0", Bytes::from_array(corrupt[:])))
  assert_true(array.read_region([0, 0], [4, 4]) is None)
  assert_true(store.put("c/0/0", shard))
  assert_eq(array.read_region([0, 0], [4, 4]), expected)
  assert_true(store.put("c/0/0", b"truncated"))
  assert_true(array.read_region([0, 0], [4, 4]) is None)
  assert_true(store.put("c/0/0", shard))
  assert_eq(array.read_region([0, 0], [4, 4]), expected)
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "cached regions support start and big endian index variants" {
  guard @fs.FileStore::new(
      "integration/fixtures/zarr-python/v3_shard_start_u8.zarr",
    )
    is Some(start) else {
    fail("start store")
  }
  guard start.open_u8("") is Some(bytes) else { fail("array") }
  assert_eq(
    bytes.read_region([0], [9]),
    Some(b"\x05\x0b\x05\x05\x05\x05\x16\x05\x21"),
  )
  assert_eq(start.shard_read_stats().index_reads, 2)
  assert_eq(start.shard_read_stats().index_cache_hits, 3)
  guard @fs.FileStore::new(
      "integration/fixtures/zarr-python/v3_shard_big_index_f32.zarr",
    )
    is Some(big) else {
    fail("big endian store")
  }
  guard big.open_f32("") is Some(floats) else { fail("array") }
  assert_eq(
    floats.read_region([0], [10]),
    Some([1.5F, 1.5F, 2.25F, 3.5F, -1.0F, 9.0F, 1.5F, 1.5F, 1.5F, 1.5F]),
  )
  assert_eq(big.shard_read_stats().index_reads, 1)
  assert_eq(big.shard_read_stats().index_cache_hits, 3)
}
