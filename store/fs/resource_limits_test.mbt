///|
async test "native object limits check size before reads and do not mask absence" {
  let dir = @async_fs.tmpdir(prefix="zarr-budget-object")
  defer @async_fs.rmdir(dir, recursive=true)
  guard @fs.FileStore::new(dir) is Some(plain) else { fail("store") }
  guard plain.create_u8(@metadata.V3, "", [4], [4], b'\x07') is Some(_) else {
    fail("array")
  }
  guard @store.ReadLimits::new(max_chunk_bytes=4) is Some(limits) else {
    fail("limits")
  }
  guard @fs.FileStore::new(dir, read_limits=limits) is Some(store) else {
    fail("store")
  }
  guard store.open_u8("") is Some(array) else { fail("array") }
  assert_eq(array.read([0]), Some(b'\x07'))
  assert_true(plain.put("c/0", b"\x01\x02\x03\x04"))
  assert_eq(array.read_region([0], [4]), Some(b"\x01\x02\x03\x04"))
  assert_true(plain.put("c/0", b"too-large"))
  let mut rejected = false
  let result = array.read([0]) catch {
    @fs.ReadLimitExceeded(_) => {
      rejected = true
      None
    }
    error => raise error
  }
  assert_true(rejected)
  assert_true(result is None)
  assert_true(plain.put("c/0", b"\x01"))
  assert_true(array.read([0]) is None)
}

///|
async test "native metadata and consolidated input budgets include exact boundary" {
  let dir = @async_fs.tmpdir(prefix="zarr-budget-metadata")
  defer @async_fs.rmdir(dir, recursive=true)
  guard @fs.FileStore::new(dir) is Some(plain) else { fail("store") }
  assert_true(
    plain.put(".zmetadata", b"{\"zarr_consolidated_format\":1,\"metadata\":{}}"),
  )
  guard plain.get(".zmetadata") is Some(raw) else { fail("index") }
  guard @store.ReadLimits::new(max_metadata_bytes=raw.length()) is Some(exact) else {
    fail("limits")
  }
  assert_true(
    @fs.FileStore::open_consolidated(dir, read_limits=exact) is Some(_),
  )
  guard @store.ReadLimits::new(max_metadata_bytes=raw.length() - 1)
    is Some(tiny) else {
    fail("limits")
  }
  let mut rejected = false
  let result = @fs.FileStore::open_consolidated(dir, read_limits=tiny) catch {
    @fs.ReadLimitExceeded(_) => {
      rejected = true
      None
    }
    error => raise error
  }
  assert_true(rejected)
  assert_true(result is None)
  assert_true(plain.put("zarr.json", b"invalid metadata"))
  assert_true(plain.open_u8("") is None)
  let deep = Bytes::make(10000, b'[').to_array()
  deep.append(Bytes::make(10000, b']').to_array()[:])
  assert_true(plain.put("zarr.json", Bytes::from_array(deep[:])))
  assert_true(plain.open_array("") is None)
  // A syntactically valid declared chunk is also rejected before fill/decode allocation.
  assert_true(
    plain.put(
      "zarr.json", b"{\"zarr_format\":3,\"node_type\":\"array\",\"shape\":[1],\"data_type\":\"uint8\",\"chunk_grid\":{\"name\":\"regular\",\"configuration\":{\"chunk_shape\":[2147483647]}},\"chunk_key_encoding\":{\"name\":\"default\"},\"fill_value\":7,\"codecs\":[{\"name\":\"bytes\"}]}",
    ),
  )
  assert_true(plain.open_u8("") is None)
  guard @store.ReadLimits::new(max_decoded_chunk_bytes=2147483647)
    is Some(trusted) else {
    fail("trusted limits")
  }
  guard @fs.FileStore::new(dir, read_limits=trusted) is Some(large) else {
    fail("store")
  }
  // Opening is allocation-free with respect to chunk contents; do not read this chunk.
  assert_true(large.open_u8("") is Some(_))
}

///|
async test "native regions preflight huge selections and all typed widths" {
  let dir = @async_fs.tmpdir(prefix="zarr-budget-region")
  defer @async_fs.rmdir(dir, recursive=true)
  guard @fs.FileStore::new(dir) is Some(plain) else { fail("store") }
  guard plain.create_u8(@metadata.V3, "huge", [2147483647], [1], b'\x06')
    is Some(huge) else {
    fail("array")
  }
  assert_true(huge.read_region([0], [2147483647]) is None)
  assert_eq(huge.read_region([2147483646], [1]), Some(b"\x06"))
  guard plain.create_u16(@metadata.V3, "words", [8], [2], 9U.to_uint16())
    is Some(_) else {
    fail("array")
  }
  guard @store.ReadLimits::new(max_region_bytes=4, max_chunks=1) is Some(limits) else {
    fail("limits")
  }
  guard @fs.FileStore::new(dir, read_limits=limits) is Some(store) else {
    fail("store")
  }
  guard store.open_u16("words") is Some(words) else { fail("array") }
  assert_true(words.read_region([0], [2]) is Some(_))
  assert_true(words.read_region([1], [2]) is None)
  assert_true(words.read_region([0], [3]) is None)
}

///|
async test "shard payload budget rejects before payload read and region before index" {
  let root = "integration/fixtures/zarr-python/v3_shard_end_gzip_u16.zarr"
  guard @store.ReadLimits::new(max_chunk_bytes=1) is Some(limits) else {
    fail("limits")
  }
  guard @fs.FileStore::new(root, read_limits=limits) is Some(store) else {
    fail("store")
  }
  guard store.open_u16("") is Some(array) else { fail("array") }
  let mut rejected = false
  let result = array.read([0, 0]) catch {
    @fs.ReadLimitExceeded(_) => {
      rejected = true
      None
    }
    error => raise error
  }
  assert_true(rejected)
  assert_true(result is None)
  assert_eq(store.shard_read_stats().index_reads, 1)
  assert_eq(store.shard_read_stats().payload_reads, 0)
  guard @store.ReadLimits::new(max_region_elements=1) is Some(one) else {
    fail("limits")
  }
  guard @fs.FileStore::new(root, read_limits=one) is Some(narrow) else {
    fail("store")
  }
  guard narrow.open_u16("") is Some(view) else { fail("array") }
  assert_true(view.read_region([0, 0], [5, 7]) is None)
  assert_eq(narrow.shard_read_stats().index_reads, 0)
}
