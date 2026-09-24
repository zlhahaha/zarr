///|
/// Native filesystem example: create, write, reopen and read a compressed
/// uint16 array. The temporary store is removed after the successful run.
async fn main {
  let dir = @async_fs.tmpdir(prefix="moonbit-zarr-demo")
  guard @fs.FileStore::new(dir) is Some(store) else {
    abort("invalid store path")
  }
  if !store.create_group_tree(@metadata.V3, "") {
    abort("root group creation failed")
  }
  guard store.create_u16(
      @metadata.V3,
      "pixels",
      [2, 3],
      [2, 2],
      (60000 : UInt16),
      compression=@codec.Zstd(3),
    )
    is Some(pixels) else {
    abort("array creation failed")
  }
  if !pixels.write_region([0, 1], [2, 2], [
      (1000 : UInt16),
      (2000 : UInt16),
      (3000 : UInt16),
      (4000 : UInt16),
    ]) {
    abort("slice write failed")
  }
  guard @fs.FileStore::new(dir) is Some(reopened) else {
    abort("reopen store failed")
  }
  guard reopened.open_u16("pixels") is Some(saved) else {
    abort("reopen array failed")
  }
  guard saved.read_region([0, 0], [2, 3]) is Some(values) else {
    abort("slice read failed")
  }
  if values !=
    [
      (60000 : UInt16),
      (1000 : UInt16),
      (2000 : UInt16),
      (60000 : UInt16),
      (3000 : UInt16),
      (4000 : UInt16),
    ] {
    abort("unexpected values")
  }
  println(
    "Zarr v3 uint16 values: \{values[0]},\{values[1]},\{values[2]},\{values[3]},\{values[4]},\{values[5]}",
  )
  @async_fs.rmdir(dir, recursive=true)
}
