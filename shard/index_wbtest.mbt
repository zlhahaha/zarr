///|
test "CRC32C matches the standard check vector" {
  assert_eq(crc32c(b"123456789"[:]), 0xE3069283U)
}

///|
test "seed 314159: CRC index mutations never become missing-fill entries" {
  let layout : @metadata.Sharding = {
    shard_shape: [4],
    chunks_per_shard: [2],
    index_size: 36,
    index_at_start: false,
    index_big_endian: false,
    index_crc32c: true,
  }
  let mut state = 314159U
  for _ in 0..<32 {
    let data = Array::makei(32, _ => {
      state = state * 1664525U + 1013904223U
      ((state >> 24) & 255U).to_byte()
    })
    let checksum = crc32c(Bytes::from_array(data[:])[:])
    for shift in [0, 8, 16, 24] {
      data.push(((checksum >> shift) & 255U).to_byte())
    }
    let valid = Bytes::from_array(data[:])
    assert_true(validate_index(layout, valid, 100L) is Some(_))
    for at in 0..<36 {
      let changed = data.copy()
      changed[at] = (changed[at].to_int() ^ 1).to_byte()
      assert_true(
        validate_index(layout, Bytes::from_array(changed[:]), 100L) is None,
      )
    }
    for end in 0..<36 {
      assert_true(validate_index(layout, valid[:end].to_owned(), 100L) is None)
    }
  }
}

///|
test "seed 161803: index entry bounds match independent interval arithmetic" {
  let mut state = 161803U
  for at_start in [false, true] {
    for big_endian in [false, true] {
      let layout : @metadata.Sharding = {
        shard_shape: [4],
        chunks_per_shard: [2],
        index_size: 32,
        index_at_start: at_start,
        index_big_endian: big_endian,
        index_crc32c: false,
      }
      for _ in 0..<128 {
        state = state * 1664525U + 1013904223U
        let offset = ((state >> 8) % 300U).reinterpret_as_int()
        state = state * 1664525U + 1013904223U
        let length = ((state >> 8) % 300U).reinterpret_as_int()
        let bytes = Array::make(32, b'\xff')
        for field in 0..<2 {
          let number = (if field == 0 { offset } else { length }).to_uint64()
          for i in 0..<8 {
            bytes[field * 8 + i] = ((
              number >> ((if big_endian { 7 - i } else { i }) * 8)
            ) &
            255UL).to_byte()
          }
        }
        let actual = entry(layout, Bytes::from_array(bytes[:]), [0], 256L)
        let lower = if at_start { 32 } else { 0 }
        let upper = if at_start { 256 } else { 224 }
        if offset >= lower &&
          offset < upper &&
          length > 0 &&
          length <= upper - offset {
          assert_true(
            actual is Data(o, n) && o == offset.to_int64() && n == length,
          )
        } else {
          assert_true(actual is Invalid)
        }
      }
    }
  }
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
