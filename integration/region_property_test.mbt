///|
test "seed 9102026: random ND overlapping writes match dense model across v2/v3 codecs" {
  let mut state = 9102026U
  fn random(bound : Int32) -> Int32 {
    state = state * 1664525U + 1013904223U
    ((state >> 8) % bound.reinterpret_as_uint()).reinterpret_as_int()
  }
  for trial in 0..<96 {
    let rank = 1 + random(4)
    let shape = Array::makei(rank, _ => 1 + random(5))
    let chunks = Array::makei(rank, _ => 1 + random(4))
    let mut count = 1
    for side in shape {
      count *= side
    }
    let model : Array[UInt16] = Array::make(count, (60000 : UInt16))
    let store = @store.MemoryStore::new()
    let format = if trial % 2 == 0 { @metadata.V2 } else { @metadata.V3 }
    let compression = match trial % 3 {
      0 => @codec.Raw
      1 => @codec.Gzip(1)
      _ => @codec.Zstd(1)
    }
    guard @array.create_u16(
        store,
        format,
        "a",
        shape,
        chunks,
        (60000 : UInt16),
        compression~,
        big_endian=trial % 4 < 2,
      )
      is Some(array) else {
      fail("create")
    }
    for operation in 0..<5 {
      let origin = Array::makei(rank, i => random(shape[i]))
      let extent = Array::makei(rank, i => 1 + random(shape[i] - origin[i]))
      let mut selected = 1
      for side in extent {
        selected *= side
      }
      let values = Array::makei(selected, i => (operation * 700 + i).to_uint16())
      assert_true(array.write_region(origin, extent, values))
      // Independent dense row-major indexing; do not use production coordinates.
      for i in 0..<selected {
        let mut remainder = i
        let mut at = 0
        let mut stride = 1
        for reverse in 0..<rank {
          let axis = rank - reverse - 1
          at += (origin[axis] + remainder % extent[axis]) * stride
          remainder /= extent[axis]
          stride *= shape[axis]
        }
        model[at] = values[i]
      }
      assert_eq(array.read_region(origin, extent), Some(values))
    }
    guard @array.open_u16(store, "a") is Some(reopened) else { fail("reopen") }
    assert_eq(reopened.read_region(Array::make(rank, 0), shape), Some(model))
    let invalid = shape.copy()
    invalid[0] += 1
    assert_true(reopened.read_region(Array::make(rank, 0), invalid) is None)
  }
}
