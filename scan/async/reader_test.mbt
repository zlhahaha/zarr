///|
async test "async reader backpressure, errors, count and early stop" {
  let mut calls = 0
  guard @async.Reader::new([5], [0], [5], [2], tile => {
      @runtime.sleep(1)
      calls += 1
      Ok(Array::make(tile.extent[0], tile.origin[0]))
    })
    is Some(reader) else {
    fail("reader")
  }
  assert_eq(calls, 0)
  guard reader.next() is Ok(Some(first)) else { fail("first") }
  assert_eq(first.values, [0, 0])
  assert_eq(calls, 1)
  reader.close()
  assert_true(reader.next() is Ok(None))
  assert_eq(calls, 1)
  guard @async.Reader::new([5], [0], [5], [2], _ => {
      calls += 1
      (
        Err(@store.Authentication("secret-free-key", 403)) :
        Result[Array[Int32], @store.AccessError])
    })
    is Some(bad) else {
    fail("bad")
  }
  assert_true(bad.next() is Err(@store.Authentication(_, 403)))
  assert_true(bad.next() is Err(@store.Authentication(_, 403)))
  assert_eq(calls, 2)
  guard @async.Reader::new([2], [0], [2], [2], _ => Ok([1])) is Some(short) else {
    fail("short")
  }
  assert_true(short.next() is Err(@store.Protocol(_, _)))
}

///|
async test "async reader rejects concurrent next without corrupting active read" {
  let mut entered = false
  guard @async.Reader::new([2], [0], [2], [1], tile => {
      entered = true
      @runtime.sleep(30)
      Ok([tile.origin[0]])
    })
    is Some(reader) else {
    fail("reader")
  }
  @runtime.with_task_group() <| group => {
    let active = group.spawn(() => reader.next())
    while !entered {
      @runtime.sleep(1)
    }
    assert_true(
      reader.next() is Err(@store.Protocol("tile", "concurrent next")),
    )
    guard active.wait() is Ok(Some(tile)) else { fail("active") }
    assert_eq(tile.values, [0])
  }
  guard reader.next() is Ok(Some(last)) else { fail("last") }
  assert_eq(last.values, [1])
  assert_true(reader.next() is Ok(None))
}

///|
suberror CallbackFailed {
  Injected
}

///|
async test "async exception propagates once and leaves a terminal error" {
  let mut calls = 0
  let read : async (@chunk.RegionTile) -> Result[
    Array[Int32],
    @store.AccessError,
  ] = _ => {
    calls += 1
    raise Injected
  }
  guard @async.Reader::new([1], [0], [1], [1], read) is Some(reader) else {
    fail("reader")
  }
  let caught = try {
    ignore(reader.next())
    false
  } catch {
    Injected => true
    _ => false
  }
  assert_true(caught)
  assert_true(reader.next() is Err(@store.Io("tile callback aborted")))
  assert_eq(calls, 1)
}

///|
async test "close during async next prevents further reads" {
  let mut entered = false
  guard @async.Reader::new([2], [0], [2], [1], tile => {
      entered = true
      @runtime.sleep(30)
      Ok([tile.origin[0]])
    })
    is Some(reader) else {
    fail("reader")
  }
  @runtime.with_task_group() <| group => {
    let active = group.spawn(() => reader.next())
    while !entered {
      @runtime.sleep(1)
    }
    reader.close()
    assert_true(active.wait() is Ok(Some(_)))
  }
  assert_true(reader.next() is Ok(None))
}

///|
async test "cancelled next cannot silently skip a tile and resume" {
  let mut entered = false
  guard @async.Reader::new([2], [0], [2], [1], _ => {
      entered = true
      @runtime.sleep(1000)
      Ok([1])
    })
    is Some(reader) else {
    fail("reader")
  }
  @runtime.with_task_group() <| group => {
    let task = group.spawn(no_wait=true, () => ignore(reader.next()))
    while !entered {
      @runtime.sleep(1)
    }
    task.cancel()
  }
  assert_true(reader.next() is Err(@store.Io("tile callback aborted")))
}
