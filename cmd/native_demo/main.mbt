///|
/// Native filesystem example: create, write, reopen and read a compressed
/// uint16 array. The temporary store is removed after the successful run.
async fn main {
  let dir = @async_fs.tmpdir(prefix="moonbit-zarr-demo")
  guard @fs.FileStore::new(dir) is Some(store) else {
    println("invalid store path")
    return
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
    println("array creation failed")
    return
  }
  if !pixels.write_region([0, 1], [2, 2], [
      (1000 : UInt16),
      (2000 : UInt16),
      (3000 : UInt16),
      (4000 : UInt16),
    ]) {
    println("slice write failed")
    return
  }
  guard @fs.FileStore::new(dir) is Some(reopened) else {
    println("reopen store failed")
    return
  }
  guard reopened.open_u16("pixels") is Some(saved) else {
    println("reopen array failed")
    return
  }
  guard saved.read_region([0, 0], [2, 3]) is Some(values) else {
    println("slice read failed")
    return
  }
  println(
    "Zarr v3 uint16 values: \{values[0]},\{values[1]},\{values[2]},\{values[3]},\{values[4]},\{values[5]}",
  )
  @async_fs.rmdir(dir, recursive=true)
}
