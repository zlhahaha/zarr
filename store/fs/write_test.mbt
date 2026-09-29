///|
async test "public put creates parents and replaces growing shrinking and empty files" {
  let dir = @async_fs.tmpdir(prefix="zarr-put-replace")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  for value in [b"old", b"longer replacement", b"x", b""] {
    assert_true(store.put("nested/c/0", value))
    assert_eq(store.get("nested/c/0"), Some(value))
    assert_eq(@async_fs.readdir("\{dir}/nested/c", include_hidden=true), ["0"])
  }
  assert_true(!store.put("../escape", b"bad"))
  assert_eq(@async_fs.readdir(dir, include_hidden=true), ["nested"])
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "real replacement failure preserves target directory and removes owned temp" {
  let dir = @async_fs.tmpdir(prefix="zarr-put-directory")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  @async_fs.mkdir("\{dir}/value")
  @async_fs.write_file(
    "\{dir}/value/marker",
    b"keep",
    create_mode=@async_fs.CreateNew,
  )
  let failed = try {
    store.put("value", b"new") |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_eq(store.get("value/marker"), Some(b"keep"))
  assert_eq(@async_fs.readdir(dir, include_hidden=true), ["value"])
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "open reader retains old file while new opens see complete replacement" {
  let dir = @async_fs.tmpdir(prefix="zarr-put-reader")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  assert_true(store.put("value", b"old"))
  {
    let reader = @async_fs.open("\{dir}/value", mode=@async_fs.ReadOnly)
    defer reader.close()
    assert_true(store.put("value", b"complete replacement"))
    assert_eq(reader.read_exactly_at(3, position=0L), b"old")
    assert_eq(store.get("value"), Some(b"complete replacement"))
  }
  assert_eq(@async_fs.readdir(dir, include_hidden=true), ["value"])
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "concurrent public writers leave complete values and no staging collisions" {
  let dir = @async_fs.tmpdir(prefix="zarr-put-concurrent")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  let values = [b"a", b"longer second", b"third", b"", b"fifth payload"]
  assert_true(store.put("shared", b"original"))
  @async.with_task_group(group => {
    for i, value in values {
      group.spawn_bg(() => {
        assert_true(store.put("shared", value))
        assert_true(store.put("separate/\{i}", value))
      })
    }
    for _ in 0..<20 {
      guard store.get("shared") is Some(value) else {
        fail("missing during replacement")
      }
      assert_true(value == b"original" || values.contains(value))
    }
  })
  guard store.get("shared") is Some(saved_value) else { fail("final value") }
  assert_true(values.contains(saved_value))
  for i, value in values {
    assert_eq(store.get("separate/\{i}"), Some(value))
  }
  let entries = @async_fs.readdir(dir, include_hidden=true)
  assert_eq(entries.length(), 2)
  assert_true(entries.contains("separate"))
  assert_true(entries.contains("shared"))
  assert_eq(
    @async_fs.readdir("\{dir}/separate", include_hidden=true).length(),
    5,
  )
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "typed region failure keeps completed earlier chunks but not partial failing chunk" {
  let dir = @async_fs.tmpdir(prefix="zarr-put-region-failure")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  guard store.create_u8(@metadata.V3, "values", [4], [2], b'\x00')
    is Some(array) else {
    fail("array")
  }
  assert_true(array.write_region([0], [2], b"\x01\x02"))
  @async_fs.mkdir("\{dir}/values/c/1")
  @async_fs.write_file(
    "\{dir}/values/c/1/marker",
    b"keep",
    create_mode=@async_fs.CreateNew,
  )
  // A filesystem error reading the second chunk stops this operation after
  // the first complete chunk has been replaced. Single-key safety is not a transaction.
  let failed = try {
    array.write_region([0], [4], b"\x03\x04\x05\x06") |> ignore
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_eq(store.get("values/c/0"), Some(b"\x03\x04"))
  assert_eq(store.get("values/c/1/marker"), Some(b"keep"))
  let entries = @async_fs.readdir("\{dir}/values/c", include_hidden=true)
  assert_eq(entries.length(), 2)
  assert_true(entries.contains("0"))
  assert_true(entries.contains("1"))
  @async_fs.rmdir(dir, recursive=true)
}
