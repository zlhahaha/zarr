///|
test "read budgets reject invalid settings and preserve inclusive boundaries" {
  assert_true(@store.ReadLimits::new(max_metadata_bytes=0) is None)
  assert_true(@store.ReadLimits::new(max_chunk_bytes=-1) is None)
  assert_true(@store.ReadLimits::new(max_decoded_chunk_bytes=0) is None)
  assert_true(@store.ReadLimits::new(max_region_bytes=0) is None)
  assert_true(@store.ReadLimits::new(max_region_elements=-1) is None)
  assert_true(@store.ReadLimits::new(max_chunks=0) is None)
  assert_true(@store.ReadLimits::new(max_rank=0) is None)
  assert_true(@store.ReadLimits::new(max_json_depth=0) is None)
  guard @store.ReadLimits::new(max_chunk_bytes=4, max_decoded_chunk_bytes=8)
    is Some(limits) else {
    fail("limits")
  }
  assert_true(limits.allows_decode(4, 8))
  assert_true(!limits.allows_decode(5, 8))
  assert_true(!limits.allows_decode(4, 9))
  assert_true(!limits.allows_decode(0, 0))
}

///|
test "memory reads preflight elements logical bytes and touched chunks" {
  guard @store.ReadLimits::new(
      max_region_elements=3,
      max_region_bytes=4,
      max_chunks=2,
    )
    is Some(limits) else {
    fail("limits")
  }
  let store = @store.MemoryStore::new(read_limits=limits)
  guard @array.create_u8(store, @metadata.V3, "u8", [8], [2], b'\x07')
    is Some(bytes) else {
    fail("array")
  }
  assert_eq(bytes.read_region([0], [3]), Some(b"\x07\x07\x07"))
  assert_true(bytes.read_region([0], [4]) is None)
  assert_eq(bytes.read_region([8], [0]), Some(b""))
  guard @array.create_u16(store, @metadata.V3, "u16", [8], [2], 7U.to_uint16())
    is Some(words) else {
    fail("array")
  }
  assert_true(words.read_region([0], [2]) is Some(_))
  assert_true(words.read_region([0], [3]) is None)
  guard @store.ReadLimits::new(max_chunks=1) is Some(one) else {
    fail("limits")
  }
  let narrow = @store.MemoryStore::new(read_limits=one)
  guard @array.create_u8(narrow, @metadata.V2, "", [8], [2], b'\x01')
    is Some(array) else {
    fail("array")
  }
  assert_true(array.read_region([0], [2]) is Some(_))
  assert_true(array.read_region([1], [2]) is None)
}

///|
test "huge valid regions reject before block enumeration or result allocation" {
  let store = @store.MemoryStore::new()
  guard @array.create_u8(store, @metadata.V3, "", [2147483647], [1], b'\x03')
    is Some(array) else {
    fail("array")
  }
  guard store.open_array("") is Some(metadata) else { fail("metadata") }
  assert_eq(
    @chunk.region_chunk_count(metadata, [0], [2147483647]),
    Some(2147483647),
  )
  assert_true(@chunk.region_chunks(metadata, [0], [2147483647]) is None)
  assert_true(array.read_region([0], [2147483647]) is None)
  assert_eq(array.read_region([2147483646], [1]), Some(b"\x03"))
  assert_true(array.read_region([2147483647], [1]) is None)
  assert_true(array.read_region([0], [16385]) is None)
  guard @store.ReadLimits::new(max_chunks=20000) is Some(trusted) else {
    fail("limits")
  }
  let bigger = @store.MemoryStore::new(read_limits=trusted)
  guard @array.create_u8(bigger, @metadata.V3, "", [20000], [1], b'\x03')
    is Some(view) else {
    fail("array")
  }
  guard view.read_region([0], [16385]) is Some(values) else {
    fail("raised chunk cap")
  }
  assert_eq(values.length(), 16385)
  assert_eq(values[16384], b'\x03')
}

///|
test "metadata decoded chunk and rank budgets reject typed opens" {
  let original = @store.MemoryStore::new()
  guard @array.create_u8(original, @metadata.V3, "", [8], [4], b'\x04')
    is Some(_) else {
    fail("array")
  }
  guard original.get("zarr.json") is Some(raw) else { fail("metadata") }
  guard @store.ReadLimits::new(max_metadata_bytes=raw.length() - 1)
    is Some(small) else {
    fail("limits")
  }
  let limited = @store.MemoryStore::new(read_limits=small)
  limited.put("zarr.json", raw)
  assert_true(limited.open_array("") is None)
  guard @store.ReadLimits::new(
      max_metadata_bytes=raw.length(),
      max_decoded_chunk_bytes=4,
    )
    is Some(exact) else {
    fail("limits")
  }
  let fits = @store.MemoryStore::new(read_limits=exact)
  fits.put("zarr.json", raw)
  assert_true(@array.open_u8(fits, "") is Some(_))
  guard @store.ReadLimits::new(max_decoded_chunk_bytes=3) is Some(tiny) else {
    fail("limits")
  }
  let chunks = @store.MemoryStore::new(read_limits=tiny)
  chunks.put("zarr.json", raw)
  assert_true(@array.open_u8(chunks, "") is None)
  guard @store.ReadLimits::new(max_rank=1) is Some(rank) else { fail("limits") }
  let ranked = @store.MemoryStore::new(read_limits=rank)
  assert_true(
    @array.create_u8(ranked, @metadata.V3, "", [2, 2], [1, 1], b'\x00') is None,
  )
}

///|
test "encoded budget and corrupted data are failures not missing fill" {
  guard @store.ReadLimits::new(max_chunk_bytes=1) is Some(limits) else {
    fail("limits")
  }
  let store = @store.MemoryStore::new(read_limits=limits)
  guard @array.create_u8(
      store,
      @metadata.V3,
      "",
      [8],
      [4],
      b'\x07',
      compression=@codec.Gzip(6),
    )
    is Some(array) else {
    fail("array")
  }
  assert_eq(array.read_region([0], [4]), Some(b"\x07\x07\x07\x07"))
  guard @codec.encode_chunk(@codec.Gzip(6), b"\x01\x02\x03\x04")
    is Some(encoded) else {
    fail("gzip")
  }
  store.put("c/0", encoded)
  assert_true(array.read([0]) is None)
  assert_true(array.read_region([0], [4]) is None)
  // The unbounded raw in-memory map accessor still returns caller-owned bytes.
  assert_eq(store.get("c/0"), Some(encoded))
  let ordinary = @store.MemoryStore::new()
  guard @array.create_u8(
      ordinary,
      @metadata.V3,
      "",
      [8],
      [4],
      b'\x07',
      compression=@codec.Gzip(6),
    )
    is Some(view) else {
    fail("array")
  }
  for length in 0..<encoded.length() {
    ordinary.put("c/0", Bytes::from_array(encoded.to_array()[:length]))
    assert_true(view.read_region([0], [4]) is None)
  }
  // A compact compressed frame expanding beyond the declared chunk is rejected.
  guard @codec.encode_chunk(@codec.Gzip(6), Bytes::make(8192, b'\x00'))
    is Some(expansion) else {
    fail("gzip")
  }
  ordinary.put("c/0", expansion)
  assert_true(view.read([0]) is None)
  ordinary.delete("c/0")
  assert_eq(view.read([0]), Some(b'\x07'))
}

///|
test "scalar and empty region counts retain their semantics" {
  let store = @store.MemoryStore::new()
  guard @array.create_u8(store, @metadata.V3, "", [], [], b'\x09')
    is Some(array) else {
    fail("scalar")
  }
  guard store.open_array("") is Some(metadata) else { fail("metadata") }
  assert_eq(@chunk.region_chunk_count(metadata, [], []), Some(1))
  assert_eq(array.read_region([], []), Some(b"\x09"))
}

///|
test "JSON depth preflight handles strings escapes malformed and deeply nested input" {
  guard @store.ReadLimits::new(max_json_depth=2) is Some(limits) else {
    fail("limits")
  }
  assert_true(limits.allows_metadata(b"{\"value\":[1]}"))
  assert_true(!limits.allows_metadata(b"{\"value\":[[1]]}"))
  assert_true(limits.allows_metadata(b"{\"value\":\"[[[\\\"{{{\"}"))
  assert_true(!limits.allows_metadata(b"{\"value\":\"unterminated}"))
  assert_true(!limits.allows_metadata(b"}"))
  assert_true(!limits.allows_metadata(b"{"))
  let data = Bytes::make(10000, b'[').to_array()
  data.append(Bytes::make(10000, b']').to_array()[:])
  let deep = Bytes::from_array(data[:])
  assert_true(!@store.ReadLimits::defaults().allows_metadata(deep))
  let store = @store.MemoryStore::new()
  store.put("zarr.json", deep)
  assert_true(store.open_array("") is None)
}

///|
test "typed numeric boolean and signed wrappers share the same budgets" {
  guard @store.ReadLimits::new(
      max_region_elements=1,
      max_region_bytes=8,
      max_decoded_chunk_bytes=8,
    )
    is Some(limits) else {
    fail("limits")
  }
  let store = @store.MemoryStore::new(read_limits=limits)
  guard @array.create_bool(store, @metadata.V3, "bool", [3], [1], true)
    is Some(booleans) else {
    fail("bool")
  }
  guard @array.create_i8(store, @metadata.V2, "i8", [3], [1], -1) is Some(i8s) else {
    fail("i8")
  }
  guard @array.create_i16(store, @metadata.V3, "i16", [3], [1], -1)
    is Some(i16s) else {
    fail("i16")
  }
  guard @array.create_u32(store, @metadata.V3, "u32", [3], [1], 1U)
    is Some(u32s) else {
    fail("u32")
  }
  guard @array.create_i64(store, @metadata.V3, "i64", [3], [1], -1L)
    is Some(i64s) else {
    fail("i64")
  }
  guard @array.create_u64(store, @metadata.V3, "u64", [3], [1], 1UL)
    is Some(u64s) else {
    fail("u64")
  }
  guard @array.create_f32(store, @metadata.V3, "f32", [3], [1], 1.0F)
    is Some(f32s) else {
    fail("f32")
  }
  guard @array.create_f64(store, @metadata.V3, "f64", [3], [1], 1.0)
    is Some(f64s) else {
    fail("f64")
  }
  assert_true(booleans.read_region([0], [1]) is Some(_))
  assert_true(i8s.read_region([0], [1]) is Some(_))
  assert_true(i16s.read_region([0], [1]) is Some(_))
  assert_true(u32s.read_region([0], [1]) is Some(_))
  assert_true(i64s.read_region([0], [1]) is Some(_))
  assert_true(u64s.read_region([0], [1]) is Some(_))
  assert_true(f32s.read_region([0], [1]) is Some(_))
  assert_true(f64s.read_region([0], [1]) is Some(_))
  assert_true(booleans.read_region([0], [2]) is None)
  assert_true(i8s.read_region([0], [2]) is None)
  assert_true(i16s.read_region([0], [2]) is None)
  assert_true(u32s.read_region([0], [2]) is None)
  assert_true(i64s.read_region([0], [2]) is None)
  assert_true(u64s.read_region([0], [2]) is None)
  assert_true(f32s.read_region([0], [2]) is None)
  assert_true(f64s.read_region([0], [2]) is None)
}

///|
test "truncated compressed chunks fail closed for all writable v3 compressors" {
  for
    plan in [
      @codec.Gzip(6),
      @codec.Zstd(1),
      @codec.ZstdChecksum(1),
      @codec.BloscLz4(5, 0, 1),
    ] {
    let store = @store.MemoryStore::new()
    guard @array.create_u8(
        store,
        @metadata.V3,
        "",
        [4],
        [4],
        b'\x07',
        compression=plan,
      )
      is Some(array) else {
      fail("array")
    }
    guard @codec.encode_chunk(plan, b"\x01\x02\x03\x04") is Some(encoded) else {
      fail("frame")
    }
    store.put("c/0", encoded)
    assert_eq(array.read_region([0], [4]), Some(b"\x01\x02\x03\x04"))
    for length in 0..<encoded.length() {
      store.put("c/0", Bytes::from_array(encoded.to_array()[:length]))
      assert_true(array.read_region([0], [4]) is None)
    }
  }
}
