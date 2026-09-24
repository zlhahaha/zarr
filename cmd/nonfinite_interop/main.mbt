///|
/// Generate two non-finite-fill stores for zarr-python to verify.
/// Existing stores are not overwritten.
async fn main {
  let base = "integration/.roundtrip"
  guard @fs.FileStore::new("\{base}/v2_f64_nan.zarr") is Some(v2_store) else {
    abort("v2 output path")
  }
  guard v2_store.create_f64(
      @metadata.V2,
      "",
      [3],
      [2],
      0x7FF8000000000000UL.reinterpret_as_double(),
      big_endian=true,
    )
    is Some(v2_array) else {
    abort("v2 NaN array creation")
  }
  if !v2_array.write([2], 42.25) {
    abort("v2 NaN array write")
  }

  guard @fs.FileStore::new("\{base}/v3_f32_neg_inf.zarr") is Some(v3_store) else {
    abort("v3 output path")
  }
  guard v3_store.create_f32(
      @metadata.V3,
      "",
      [3],
      [2],
      Float::reinterpret_from_uint(0xFF800000U),
    )
    is Some(v3_array) else {
    abort("v3 infinity array creation")
  }
  if !v3_array.write([2], 1.25) {
    abort("v3 infinity array write")
  }
  println("MoonBit non-finite-fill stores created")
}
