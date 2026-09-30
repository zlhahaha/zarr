///|
test "tiles traverse a rectangle in C order without allocating it" {
  guard @chunk.RegionTileCursor::new(
      [100000, 100000],
      [2, 3],
      [5, 7],
      [2, 3],
      max_tile_elements=6,
    )
    is Some(cursor) else {
    fail("tile cursor")
  }
  let origins : Array[Array[Int]] = []
  let extents : Array[Array[Int]] = []
  while cursor.next() is Some(tile) {
    origins.push(tile.origin)
    extents.push(tile.extent)
  }
  assert_eq(origins, [
    [2, 3],
    [2, 6],
    [2, 9],
    [4, 3],
    [4, 6],
    [4, 9],
    [6, 3],
    [6, 6],
    [6, 9],
  ])
  assert_eq(extents, [
    [2, 3],
    [2, 3],
    [2, 1],
    [2, 3],
    [2, 3],
    [2, 1],
    [1, 3],
    [1, 3],
    [1, 1],
  ])
  assert_true(cursor.next() is None)
}

///|
test "tiles validate bounds, allow empty and scalar selections" {
  assert_true(@chunk.RegionTileCursor::new([4], [3], [2], [1]) is None)
  assert_true(@chunk.RegionTileCursor::new([4], [0], [4], [0]) is None)
  assert_true(
    @chunk.RegionTileCursor::new([4], [0], [4], [3], max_tile_elements=2)
    is None,
  )
  guard @chunk.RegionTileCursor::new([4], [0], [0], [2]) is Some(empty) else {
    fail("empty")
  }
  assert_true(empty.next() is None)
  guard @chunk.RegionTileCursor::new([], [], [], []) is Some(scalar) else {
    fail("scalar")
  }
  guard scalar.next() is Some(tile) else { fail("scalar tile") }
  assert_eq(tile.origin, [])
  assert_eq(tile.extent, [])
  assert_true(scalar.next() is None)
}
