///|
test "Blosc LZ4 arrays write and reopen across formats" {
  for format in [@metadata.V2, @metadata.V3] {
    let store = @store.MemoryStore::new()
    guard create_u16(
        store,
        format,
        "samples",
        [5],
        [4],
        (7 : UInt16),
        compression=@codec.BloscLz4(5, 2, 2),
      )
      is Some(array) else {
      fail("Blosc array creation")
    }
    assert_true(array.write([0], (20 : UInt16)))
    assert_true(array.write([4], (30 : UInt16)))
    guard open_u16(store, "samples") is Some(reopened) else {
      fail("Blosc array reopen")
    }
    assert_eq(
      reopened.read_region([0], [5]),
      Some([
        (20 : UInt16),
        (7 : UInt16),
        (7 : UInt16),
        (7 : UInt16),
        (30 : UInt16),
      ]),
    )
  }
}

///|
test "Blosc LZ4 creation rejects invalid configuration" {
  let store = @store.MemoryStore::new()
  assert_true(
    create_u16(
      store,
      @metadata.V3,
      "wrong_typesize",
      [4],
      [4],
      (0 : UInt16),
      compression=@codec.BloscLz4(5, 1, 1),
    )
    is None,
  )
  assert_true(
    create_u16(
      store,
      @metadata.V2,
      "wrong_level",
      [4],
      [4],
      (0 : UInt16),
      compression=@codec.BloscLz4(10, 1, 2),
    )
    is None,
  )
  assert_true(
    create_u16(
      store,
      @metadata.V2,
      "wrong_shuffle",
      [4],
      [4],
      (0 : UInt16),
      compression=@codec.BloscLz4(5, 3, 2),
    )
    is None,
  )
}
