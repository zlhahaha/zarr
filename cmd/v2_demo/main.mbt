///|
/// Native v2 example: create, write, reopen and read a gzip-compressed,
/// big-endian signed array. A failed step exits with an error.
async fn main {
  let dir = @async_fs.tmpdir(prefix="moonbit-zarr-v2-demo")
  guard @fs.FileStore::new(dir) is Some(store) else {
    abort("invalid store path")
  }
  if !store.create_group_tree(@metadata.V2, "") {
    abort("root group creation failed")
  }
  guard store.create_i16(
      @metadata.V2,
      "signal",
      [3, 4],
      [2, 2],
      (-1234 : Int16),
      big_endian=true,
      compression=@codec.Gzip(1),
    )
    is Some(signal) else {
    abort("array creation failed")
  }
  if !signal.write_region([1, 1], [2, 3], [
      (-10 : Int16),
      (20 : Int16),
      (30 : Int16),
      (40 : Int16),
      (-50 : Int16),
      (60 : Int16),
    ]) {
    abort("slice write failed")
  }
  guard @fs.FileStore::new(dir) is Some(reopened) else {
    abort("reopen store failed")
  }
  guard reopened.open_i16("signal") is Some(saved) else {
    abort("reopen array failed")
  }
  guard saved.read_region([0, 0], [3, 4]) is Some(values) else {
    abort("slice read failed")
  }
  if values !=
    [
      (-1234 : Int16),
      (-1234 : Int16),
      (-1234 : Int16),
      (-1234 : Int16),
      (-1234 : Int16),
      (-10 : Int16),
      (20 : Int16),
      (30 : Int16),
      (-1234 : Int16),
      (40 : Int16),
      (-50 : Int16),
      (60 : Int16),
    ] {
    abort("unexpected values")
  }
  println("Zarr v2 int16 values: \{values.length()} checked")
  @async_fs.rmdir(dir, recursive=true)
}
