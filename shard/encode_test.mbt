///|
test "packed shards match index entries for every index encoding and location" {
  for at_start in [false, true] {
    for big_endian in [false, true] {
      for crc in [false, true] {
        let layout : @metadata.Sharding = {
          shard_shape: [4],
          chunks_per_shard: [2],
          index_size: 32 + (if crc { 4 } else { 0 }),
          index_at_start: at_start,
          index_big_endian: big_endian,
          index_crc32c: crc,
        }
        guard @shard.encode(layout, [Some(b"abc"), None]) is Some(bytes) else {
          fail("encode")
        }
        let start = if at_start { layout.index_size } else { 0 }
        assert_eq(bytes[start:start + 3].to_owned(), b"abc")
        let index_at = if at_start { 0 } else { 3 }
        let index = bytes[index_at:index_at + layout.index_size].to_owned()
        assert_true(
          @shard.entry(layout, index, [0], bytes.length().to_int64())
          is @shard.Data(at, 3) &&
          at == start.to_int64(),
        )
        assert_true(
          @shard.entry(layout, index, [1], bytes.length().to_int64())
          is @shard.Absent,
        )
        assert_true(
          @shard.encode(
            layout,
            [Some(b"abc"), None],
            max_bytes=bytes.length() - 1,
          )
          is None,
        )
        assert_true(@shard.encode(layout, [Some(b""), None]) is None)
        assert_true(@shard.encode(layout, [None]) is None)
        guard @shard.encode(layout, [None, None]) is Some(empty) else {
          fail("empty")
        }
        assert_eq(empty.length(), layout.index_size)
        assert_true(
          @shard.entry(layout, empty, [0], empty.length().to_int64())
          is @shard.Absent,
        )
      }
    }
  }
}
