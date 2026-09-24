///|
async test "native int8 array reopens with signed slices" {
  let dir = @async_fs.tmpdir(prefix="zarr-i8-test")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  guard store.create_i8(
      @metadata.V3,
      "signed",
      [3],
      [2],
      -5,
      compression=@codec.Zstd(3),
    )
    is Some(array) else {
    fail("create int8")
  }
  assert_true(array.write_region([1], [2], [-128, 127]))
  guard @fs.FileStore::new(dir) is Some(reopened) else { fail("reopen") }
  guard reopened.open_i8("signed") is Some(saved) else { fail("open int8") }
  assert_eq(saved.read_region([0], [3]), Some([-5, -128, 127]))
  assert_true(!saved.write([0], 128))
  assert_true(reopened.open_u8("signed") is None)
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "read independent zarr-python signed-byte fixtures" {
  let base = "integration/fixtures/zarr-python"
  for path in ["v2_i8.zarr", "v3_i8_zstd.zarr"] {
    guard @fs.FileStore::new("\{base}/\{path}") is Some(store) else {
      fail("int8 fixture store")
    }
    guard store.open_i8("") is Some(array) else { fail("int8 fixture") }
    assert_eq(array.read_region([0], [3]), Some([-5, -128, 127]))
  }
}
