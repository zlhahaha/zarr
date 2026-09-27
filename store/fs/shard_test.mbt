///|
async test "read zarr-python sharding with end index, gzip and edge shards" {
  guard @fs.FileStore::new(
      "integration/fixtures/zarr-python/v3_shard_end_gzip_u16.zarr",
    )
    is Some(store) else {
    fail("shard fixture path")
  }
  guard store.open_u16("") is Some(array) else { fail("sharded uint16 open") }
  assert_eq(array.read([0, 0]), Some((7 : UInt16)))
  assert_eq(array.read([0, 1]), Some((100 : UInt16)))
  assert_eq(array.read([2, 5]), Some((114 : UInt16)))
  assert_eq(array.read([4, 6]), Some((7 : UInt16)))
  guard array.read_region([0, 0], [5, 7]) is Some(values) else {
    fail("sharded uint16 full read")
  }
  assert_eq(values.length(), 35)
  for row in 0..<5 {
    for column in 0..<7 {
      let expected = if row < 3 && column >= 1 && column < 6 {
        (100 + row * 5 + column - 1).to_uint16()
      } else {
        (7 : UInt16)
      }
      assert_eq(values[row * 7 + column], expected)
    }
  }
  assert_true(!array.write([0, 0], (99 : UInt16)))
}

///|
async test "read start-index shard with absent chunks and boundary shard" {
  guard @fs.FileStore::new(
      "integration/fixtures/zarr-python/v3_shard_start_u8.zarr",
    )
    is Some(store) else {
    fail("start shard fixture path")
  }
  guard store.open_u8("") is Some(array) else {
    fail("start sharded uint8 open")
  }
  assert_eq(
    array.read_region([0], [9]),
    Some(b"\x05\x0b\x05\x05\x05\x05\x16\x05\x21"),
  )
  assert_true(!array.write([1], b'\x44'))
}

///|
async test "read big-endian shard index without checksum" {
  guard @fs.FileStore::new(
      "integration/fixtures/zarr-python/v3_shard_big_index_f32.zarr",
    )
    is Some(store) else {
    fail("big index fixture path")
  }
  guard store.open_f32("") is Some(array) else {
    fail("big index float32 open")
  }
  assert_eq(array.read([0]), Some(1.5F))
  assert_eq(array.read([2]), Some(2.25F))
  assert_eq(array.read([5]), Some(9.0F))
  assert_eq(array.read([9]), Some(1.5F))
}

///|
async test "read Blosc-compressed inner chunks" {
  guard @fs.FileStore::new(
      "integration/fixtures/zarr-python/v3_shard_blosc_u16.zarr",
    )
    is Some(store) else {
    fail("Blosc shard fixture path")
  }
  guard store.open_u16("") is Some(array) else { fail("Blosc shard open") }
  assert_eq(array.read([2]), Some((0 : UInt16)))
  assert_eq(array.read([3]), Some((200 : UInt16)))
  assert_eq(array.read([22]), Some((219 : UInt16)))
  assert_eq(array.read([23]), Some((0 : UInt16)))
}
