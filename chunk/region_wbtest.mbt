///|
fn next_small(seed : UInt, bound : Int) -> (UInt, Int) {
  let next = seed * 1664525U + 1013904223U
  (next, ((next >> 8) % bound.reinterpret_as_uint()).reinterpret_as_int())
}

///|
fn test_metadata(
  shape : Array[Int],
  chunk_shape : Array[Int],
) -> @metadata.ArrayMetadata {
  {
    format: @metadata.V3,
    shape,
    chunk_shape,
    data_type: "uint8",
    separator: "/",
    key_encoding: "default",
    codecs: [Json::string("bytes")],
    v2_filter_count: 0,
    storage_transformers: [],
    fill_value: Json::number(0.0),
    order: "C",
  }
}

///|
test "region chunks partition every bounded rectangle exactly once" {
  let mut seed = 7U
  for _ in 0..<120 {
    let (next, rank_offset) = next_small(seed, 3)
    seed = next
    let rank = rank_offset + 1
    let shape : Array[Int] = []
    let chunks : Array[Int] = []
    let origin : Array[Int] = []
    let extent : Array[Int] = []
    for _ in 0..<rank {
      let (next, side_offset) = next_small(seed, 7)
      seed = next
      let side = side_offset + 1
      let (next, chunk_offset) = next_small(seed, side)
      seed = next
      let chunk = chunk_offset + 1
      let (next, start) = next_small(seed, side)
      seed = next
      let (next, size_offset) = next_small(seed, side - start)
      seed = next
      shape.push(side)
      chunks.push(chunk)
      origin.push(start)
      extent.push(size_offset + 1)
    }
    let metadata = test_metadata(shape, chunks)
    guard region_len(metadata, origin, extent) is Some(length) else {
      fail("valid region")
    }
    guard region_chunks(metadata, origin, extent) is Some(pieces) else {
      fail("valid chunk partition")
    }
    let mut expected_chunks = 1
    for axis in 0..<rank {
      let first = origin[axis] / chunks[axis]
      let last = (origin[axis] + extent[axis] - 1) / chunks[axis]
      expected_chunks *= last - first + 1
    }
    assert_eq(pieces.length(), expected_chunks)
    for linear in 0..<length {
      let indices = region_coords(origin, extent, linear)
      assert_eq(region_index(origin, extent, indices), Some(linear))
      let mut covering = 0
      for piece in pieces {
        let mut inside = true
        for axis in 0..<rank {
          if indices[axis] < piece.origin[axis] ||
            indices[axis] >= piece.origin[axis] + piece.extent[axis] {
            inside = false
          }
        }
        if inside {
          covering += 1
          for axis in 0..<rank {
            assert_eq(piece.coordinates[axis], indices[axis] / chunks[axis])
          }
        }
      }
      assert_eq(covering, 1)
    }
  }
}
