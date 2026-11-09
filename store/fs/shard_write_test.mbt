///|
async test "whole uint8 shard replacement clips edges and rejects partial APIs without changes" {
  let dir = @async_fs.tmpdir(prefix="zarr-shard-write")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  guard store.create_sharded_u8(
      "a",
      [9],
      [2],
      [4],
      b'\x05',
      compression=@codec.Gzip(1),
      index_at_start=true,
    )
    is Some(array) else {
    fail("create")
  }
  assert_true(array.write_shard([0], b"\x01\x02\x03\x04"))
  assert_true(array.write_shard([2], b"\x09"))
  assert_eq(
    array.read_region([0], [9]),
    Some(b"\x01\x02\x03\x04\x05\x05\x05\x05\x09"),
  )
  let before = store.get("a/c/0")
  assert_true(!array.write_shard([0], b"short"))
  assert_true(!array.write_shard([3], b"\x01"))
  assert_true(!array.write([0], b'\x10'))
  assert_true(!array.write_region([0], [2], b"\x10\x20"))
  assert_eq(store.get("a/c/0"), before)
  assert_true(array.write_shard([0], b"\x0b\x0c\x0d\x0e"))
  guard store.open_u8("a") is Some(reopened) else { fail("reopen") }
  assert_eq(
    reopened.read_region([0], [9]),
    Some(b"\x0b\x0c\x0d\x0e\x05\x05\x05\x05\x09"),
  )
  // Complete replacement need not decode an old damaged shard.
  assert_true(store.put("a/c/0", b"damaged"))
  assert_true(array.write_shard([0], b"\x01\x02\x03\x04"))
  assert_eq(array.read([0]), Some(b'\x01'))
  assert_true(store.create_sharded_u8("a", [9], [2], [4], b'\x00') is None)
  assert_true(store.create_sharded_u8("bad", [9], [3], [4], b'\x00') is None)
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "shard byte budget rejection leaves existing target untouched" {
  let dir = @async_fs.tmpdir(prefix="zarr-shard-budget")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  guard store.create_sharded_u8("a", [4], [2], [4], b'\x05') is Some(array) else {
    fail("create")
  }
  assert_true(array.write_shard([0], b"abcd"))
  let before = store.get("a/c/0")
  guard @store.ReadLimits::new(max_chunk_bytes=38) is Some(limits) else {
    fail("limits")
  }
  guard @fs.FileStore::new(dir, read_limits=limits) is Some(limited) else {
    fail("limited")
  }
  guard limited.open_u8("a") is Some(array) else { fail("open") }
  assert_true(!array.write_shard([0], b"efgh"))
  assert_eq(store.get("a/c/0"), before)
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "scalar and zero-extent sharded arrays preserve rank and reject invalid writes" {
  let dir = @async_fs.tmpdir(prefix="zarr-shard-scalar")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  guard store.create_sharded_u8("scalar", [], [], [], b'\x05') is Some(scalar) else {
    fail("scalar")
  }
  assert_eq(scalar.read([]), Some(b'\x05'))
  assert_true(scalar.write_shard([], b"\x09"))
  assert_eq(scalar.read([]), Some(b'\x09'))
  assert_true(!scalar.write_shard([0], b"\x0a"))
  assert_true(!scalar.write_shard([], b""))
  assert_eq(scalar.read([]), Some(b'\x09'))
  guard store.create_sharded_u8("empty", [0, 3], [2, 2], [4, 4], b'\x05')
    is Some(empty) else {
    fail("empty")
  }
  assert_eq(empty.read_region([0, 0], [0, 3]), Some(b""))
  assert_true(!empty.write_shard([0, 0], b""))
  assert_eq(store.get("empty/c/0/0"), None)
  @async_fs.rmdir(dir, recursive=true)
}
