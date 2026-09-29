///|
/// Image volumes and time-space-feature tensors share the same region API.
async fn main {
  let dir = @async_fs.tmpdir(prefix="zarr-nd-demo")
  guard @fs.FileStore::new(dir) is Some(store) else { abort("store") }
  guard store.create_u16(
      @metadata.V3,
      "volume",
      [5, 7, 9],
      [2, 3, 4],
      (0 : UInt16),
      compression=@codec.Gzip(1),
    )
    is Some(volume) else {
    abort("volume")
  }
  let pixels : Array[UInt16] = []
  for i in 0..<96 {
    pixels.push((i + 100).to_uint16())
  }
  if !volume.write_region([1, 1, 1], [4, 3, 8], pixels) {
    abort("volume write")
  }
  guard store.create_f32(
      @metadata.V3,
      "features",
      [3, 5, 7, 4],
      [2, 2, 3, 3],
      -1.5,
      compression=@codec.Zstd(3),
    )
    is Some(features) else {
    abort("features")
  }
  let values : Array[Float] = []
  for i in 0..<72 {
    values.push(Float::from_int(i) / 4.0)
  }
  if !features.write_region([1, 1, 1, 1], [2, 2, 6, 3], values) {
    abort("features write")
  }
  guard @fs.FileStore::new(dir) is Some(reopened) else { abort("reopen") }
  guard reopened.open_u16("volume") is Some(saved_volume) else {
    abort("open volume")
  }
  guard reopened.open_f32("features") is Some(saved_features) else {
    abort("open features")
  }
  if saved_volume.read_region([1, 1, 1], [4, 3, 8]) != Some(pixels) ||
    saved_features.read_region([1, 1, 1, 1], [2, 2, 6, 3]) != Some(values) ||
    saved_volume.read([4, 6, 8]) != Some((0 : UInt16)) ||
    saved_features.read([2, 4, 6, 3]) != Some(-1.5F) {
    abort("N-D values or missing fills differ")
  }
  @async_fs.rmdir(dir, recursive=true)
  println(
    "Zarr N-D: 3D volume (96 values), 4D features (72 values), reopen and fills verified",
  )
}
