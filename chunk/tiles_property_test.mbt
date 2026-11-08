///|
test "seed 20261109: 400 random ND tile plans exactly cover independent coordinate model" {
  let mut state = 20261109U
  fn random(bound : Int32) -> Int32 {
    state = state * 1664525U + 1013904223U
    ((state >> 8) % bound.reinterpret_as_uint()).reinterpret_as_int()
  }
  for _ in 0..<400 {
    let rank = random(5)
    let shape = Array::makei(rank, _ => random(6) + 1)
    let origin = Array::makei(rank, i => random(shape[i] + 1))
    let extent = Array::makei(rank, i => random(shape[i] - origin[i] + 1))
    let tile_shape = Array::makei(rank, _ => random(5) + 1)
    let mut total = 1
    for side in extent {
      total *= side
    }
    let seen = Array::make(total, false)
    guard @chunk.RegionTileCursor::new(shape, origin, extent, tile_shape)
      is Some(cursor) else {
      fail("valid plan")
    }
    let mut visited = 0
    let mut tile_count = 0
    while cursor.next() is Some(tile) {
      tile_count += 1
      assert_true(tile_count <= total)
      let mut count = 1
      for i in 0..<rank {
        assert_true(tile.origin[i] >= origin[i])
        assert_true(tile.extent[i] > 0 && tile.extent[i] <= tile_shape[i])
        assert_true(tile.origin[i] + tile.extent[i] <= origin[i] + extent[i])
        count *= tile.extent[i]
      }
      for flat in 0..<count {
        let mut remainder = flat
        let mut offset = 0
        let mut stride = 1
        for reverse in 0..<rank {
          let i = rank - 1 - reverse
          let coordinate = remainder % tile.extent[i]
          remainder /= tile.extent[i]
          offset += (tile.origin[i] - origin[i] + coordinate) * stride
          stride *= extent[i]
        }
        assert_true(!seen[offset])
        seen[offset] = true
        visited += 1
      }
    }
    assert_eq(visited, total)
    for value in seen {
      assert_true(value)
    }
    assert_true(cursor.next() is None)
  }
}
