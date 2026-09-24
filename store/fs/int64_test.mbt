///|
async test "native v2 int64 preserves full-range fill and region writes" {
  let dir = @async_fs.tmpdir(prefix="zarr-i64-test")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  guard store.create_i64(
      @metadata.V2,
      "signed",
      [3],
      [2],
      -9223372036854775807L,
      big_endian=true,
    )
    is Some(array) else {
    fail("create int64")
  }
  assert_true(array.write_region([1], [2], [0L, 9223372036854775807L]))
  guard @fs.FileStore::new(dir) is Some(reopened) else { fail("reopen") }
  guard reopened.open_i64("signed") is Some(saved) else { fail("open int64") }
  assert_eq(
    saved.read_region([0], [3]),
    Some([-9223372036854775807L, 0L, 9223372036854775807L]),
  )
  assert_true(reopened.open_u64("signed") is None)
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "native v3 uint64 round-trips compressed values" {
  let dir = @async_fs.tmpdir(prefix="zarr-u64-test")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  guard store.create_u64(
      @metadata.V3,
      "unsigned",
      [3],
      [2],
      18446744073709551615UL,
      compression=@codec.Zstd(3),
    )
    is Some(array) else {
    fail("create uint64")
  }
  assert_true(array.write_region([1], [2], [0UL, 18446744073709551614UL]))
  guard @fs.FileStore::new(dir) is Some(reopened) else { fail("reopen") }
  guard reopened.open_u64("unsigned") is Some(saved) else {
    fail("open uint64")
  }
  assert_eq(
    saved.read_region([0], [3]),
    Some([18446744073709551615UL, 0UL, 18446744073709551614UL]),
  )
  assert_true(reopened.open_i64("unsigned") is None)
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "read independent zarr-python full-range 64-bit fixtures" {
  let base = "integration/fixtures/zarr-python"
  guard @fs.FileStore::new("\{base}/v2_i64_be.zarr") is Some(v2_store) else {
    fail("v2 int64 fixture")
  }
  guard v2_store.open_i64("") is Some(v2_array) else { fail("v2 int64 array") }
  assert_eq(
    v2_array.read_region([0], [3]),
    Some([-9223372036854775807L, -9223372036854775807L, 9223372036854775807L]),
  )

  guard @fs.FileStore::new("\{base}/v3_u64_le_zstd.zarr") is Some(v3_store) else {
    fail("v3 uint64 fixture")
  }
  guard v3_store.open_u64("") is Some(v3_array) else { fail("v3 uint64 array") }
  assert_eq(
    v3_array.read_region([0], [3]),
    Some([
      18446744073709551615UL, 18446744073709551615UL, 18446744073709551614UL,
    ]),
  )
}
