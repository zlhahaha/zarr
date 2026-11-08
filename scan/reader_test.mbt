///|
test "pull reader is lazy, validates count, preserves errors and closes" {
  let mut calls = 0
  guard @scan.Reader::new([7], [1], [6], [4], tile => {
      calls += 1
      Ok(Array::make(tile.extent[0], tile.origin[0]))
    })
    is Some(reader) else {
    fail("reader")
  }
  assert_eq(calls, 0)
  guard reader.next() is Ok(Some(tile)) else { fail("tile") }
  assert_eq(tile.origin, [1])
  assert_eq(tile.extent, [4])
  assert_eq(tile.values, [1, 1, 1, 1])
  reader.close()
  assert_true(reader.next() is Ok(None))
  assert_eq(calls, 1)
  guard @scan.Reader::new([2], [0], [2], [1], _ => {
      calls += 1
      (Err(@store.Timeout("source")) : Result[Array[Int32], @store.AccessError])
    })
    is Some(bad) else {
    fail("bad")
  }
  assert_true(bad.next() is Err(@store.Timeout("source")))
  assert_true(bad.next() is Err(@store.Timeout("source")))
  assert_eq(calls, 2)
  guard @scan.Reader::new([1], [0], [1], [1], _ => Ok([1, 2])) is Some(short) else {
    fail("short")
  }
  assert_true(short.next() is Err(@store.Protocol(_, _)))
}

///|
test "reader scalar empty selection and descriptor ownership" {
  guard @scan.Reader::new([], [], [], [], _ => Ok([42])) is Some(scalar) else {
    fail("scalar")
  }
  guard scalar.next() is Ok(Some(tile)) else { fail("scalar value") }
  assert_eq(tile.values, [42])
  assert_true(scalar.next() is Ok(None))
  guard @scan.Reader::new([2], [2], [0], [1], _ => Ok([42])) is Some(empty) else {
    fail("empty")
  }
  assert_true(empty.next() is Ok(None))
  guard @scan.Reader::new([2], [0], [2], [1], tile => {
      tile.origin[0] = 99
      tile.extent[0] = 99
      Ok([42])
    })
    is Some(owned) else {
    fail("owned")
  }
  guard owned.next() is Ok(Some(first)) else { fail("first") }
  assert_eq(first.origin, [0])
  assert_eq(first.extent, [1])
  first.origin[0] = 77
  guard owned.next() is Ok(Some(second)) else { fail("second") }
  assert_eq(second.origin, [1])
}
