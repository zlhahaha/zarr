///|
/// Generate signed-byte stores for zarr-python to verify.
/// Existing stores are not overwritten.
async fn main {
  let base = "integration/.roundtrip"
  guard @fs.FileStore::new("\{base}/v2_i8.zarr") is Some(v2_store) else {
    abort("v2 int8 output path")
  }
  guard v2_store.create_i8(@metadata.V2, "", [3], [2], -5) is Some(v2_array) else {
    abort("v2 int8 creation")
  }
  if !v2_array.write_region([1], [2], [-128, 127]) {
    abort("v2 int8 write")
  }

  guard @fs.FileStore::new("\{base}/v3_i8_zstd.zarr") is Some(v3_store) else {
    abort("v3 int8 output path")
  }
  guard v3_store.create_i8(
      @metadata.V3,
      "",
      [3],
      [2],
      -5,
      compression=@codec.Zstd(3),
    )
    is Some(v3_array) else {
    abort("v3 int8 creation")
  }
  if !v3_array.write_region([1], [2], [-128, 127]) {
    abort("v3 int8 write")
  }
  println("MoonBit signed-byte stores created")
}
