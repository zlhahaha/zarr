///|
test "portable 3D uint16 cross-chunk read/write and fills in v2/v3" {
  for format in [@metadata.V2, @metadata.V3] {
    for compression in [@codec.Raw, @codec.Gzip(1), @codec.Zstd(3)] {
      let store = @store.MemoryStore::new()
      guard @array.create_u16(
          store,
          format,
          "image",
          [5, 7, 9],
          [2, 3, 4],
          (60000 : UInt16),
          big_endian=true,
          compression~,
        )
        is Some(array) else {
        fail("create")
      }
      let values : Array[UInt16] = []
      for x in 1..<5 {
        for y in 1..<4 {
          for z in 1..<9 {
            values.push((1000 * x + 100 * y + z + 1).to_uint16())
          }
        }
      }
      assert_true(array.write_region([1, 1, 1], [4, 3, 8], values))
      guard @array.open_u16(store, "image") is Some(saved) else {
        fail("reopen")
      }
      guard saved.read_region([0, 0, 0], [5, 7, 9]) is Some(actual) else {
        fail("read")
      }
      for i in 0..<actual.length() {
        let p = @chunk.region_coords([0, 0, 0], [5, 7, 9], i)
        let expected = if p[0] >= 1 && p[1] >= 1 && p[1] < 4 && p[2] >= 1 {
          (1000 * p[0] + 100 * p[1] + p[2] + 1).to_uint16()
        } else {
          (60000 : UInt16)
        }
        assert_eq(actual[i], expected)
      }
      assert_eq(saved.read_region([5, 0, 0], [0, 7, 9]), Some([]))
      assert_eq(saved.read_region([4, 0, 0], [2, 1, 1]), None)
    }
  }
}

///|
test "portable 4D F-order float32 maps to C-order regions" {
  let store = @store.MemoryStore::new()
  let raw =
    #|{"zarr_format":2,"shape":[3,5,7,4],"chunks":[2,2,3,3],"dtype":">f4","order":"F","fill_value":-1.5,"compressor":{"id":"zlib","level":1},"filters":null}
  assert_true(store.put_array_metadata(@metadata.V2, "features", raw))
  guard @array.open_f32(store, "features") is Some(array) else { fail("open") }
  let values : Array[Float] = []
  for t in 1..<3 {
    for y in 1..<3 {
      for z in 1..<7 {
        for c in 1..<4 {
          values.push(
            Float::from_int(100 * t + 10 * y + z - 50) +
            Float::from_int(c) / 4.0,
          )
        }
      }
    }
  }
  assert_true(array.write_region([1, 1, 1, 1], [2, 2, 6, 3], values))
  guard array.read_region([0, 0, 0, 0], [3, 5, 7, 4]) is Some(actual) else {
    fail("read")
  }
  for i in 0..<actual.length() {
    let p = @chunk.region_coords([0, 0, 0, 0], [3, 5, 7, 4], i)
    let expected : Float = if p[0] >= 1 &&
      p[1] >= 1 &&
      p[1] < 3 &&
      p[2] >= 1 &&
      p[3] >= 1 {
      Float::from_int(100 * p[0] + 10 * p[1] + p[2] - 50) +
      Float::from_int(p[3]) / 4.0
    } else {
      -1.5
    }
    assert_eq(actual[i], expected)
  }
}

///|
test "optimized scalar and empty region reads retain fill semantics" {
  let store = @store.MemoryStore::new()
  guard @array.create_u8(store, @metadata.V3, "scalar", [], [], b'\x07')
    is Some(scalar) else {
    fail("scalar")
  }
  assert_eq(scalar.read_region([], []), Some(b"\x07"))
  assert_true(scalar.write_region([], [], b"\x09"))
  assert_eq(scalar.read_region([], []), Some(b"\x09"))
  guard @array.create_f32(
      store,
      @metadata.V3,
      "empty",
      [3, 0, 7, 4],
      [2, 2, 3, 3],
      -1.5,
    )
    is Some(empty) else {
    fail("empty")
  }
  assert_eq(empty.read_region([0, 0, 0, 0], [3, 0, 7, 4]), Some([]))
}
