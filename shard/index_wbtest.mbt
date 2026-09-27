///|
test "CRC32C matches the standard check vector" {
  assert_eq(crc32c(b"123456789"[:]), 0xE3069283U)
}

///|
test "shard index distinguishes absent data from corruption" {
  let layout : @metadata.Sharding = {
    shard_shape: [4],
    chunks_per_shard: [2],
    index_size: 32,
    index_at_start: false,
    index_big_endian: false,
    index_crc32c: false,
  }
  let index = b"\x00\x00\x00\x00\x00\x00\x00\x00\x04\x00\x00\x00\x00\x00\x00\x00\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff"
  assert_true(entry(layout, index, [0], 36L) is Data(0L, 4))
  assert_true(entry(layout, index, [1], 36L) is Absent)
  assert_true(entry(layout, index, [2], 36L) is Invalid)
  let broken = index.to_array()
  broken[24] = b'\x00'
  assert_true(entry(layout, Bytes::from_array(broken[:]), [1], 36L) is Invalid)
  broken[24] = b'\xff'
  broken[0] = b'\x05'
  assert_true(entry(layout, Bytes::from_array(broken[:]), [0], 36L) is Invalid)
}

///|
test "shard index validates CRC32C before reading an entry" {
  let layout : @metadata.Sharding = {
    shard_shape: [4],
    chunks_per_shard: [2],
    index_size: 36,
    index_at_start: false,
    index_big_endian: false,
    index_crc32c: true,
  }
  let data = b"\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff"
  let checked = data.to_array()
  let checksum = crc32c(data[:])
  for shift in [0, 8, 16, 24] {
    checked.push(((checksum >> shift) & 255U).to_byte())
  }
  assert_true(entry(layout, Bytes::from_array(checked[:]), [0], 36L) is Absent)
  checked[0] = b'\x00'
  assert_true(entry(layout, Bytes::from_array(checked[:]), [0], 36L) is Invalid)
}
