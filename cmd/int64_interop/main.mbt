///|
/// Generate full-range 64-bit stores for zarr-python to verify.
/// Existing stores are not overwritten.
async fn main {
  let base = "integration/.roundtrip"
  guard @fs.FileStore::new("\{base}/v2_i64_be.zarr") is Some(v2_store) else {
    abort("v2 int64 output path")
  }
  guard v2_store.create_i64(
      @metadata.V2,
      "",
      [3],
      [2],
      -9223372036854775807L,
      big_endian=true,
    )
    is Some(v2_array) else {
    abort("v2 int64 creation")
  }
  if !v2_array.write([2], 9223372036854775807L) {
    abort("v2 int64 write")
  }

  guard @fs.FileStore::new("\{base}/v3_u64_le_zstd.zarr") is Some(v3_store) else {
    abort("v3 uint64 output path")
  }
  guard v3_store.create_u64(
      @metadata.V3,
      "",
      [3],
      [2],
      18446744073709551615UL,
      compression=@codec.Zstd(3),
    )
    is Some(v3_array) else {
    abort("v3 uint64 creation")
  }
  if !v3_array.write([2], 18446744073709551614UL) {
    abort("v3 uint64 write")
  }
  println("MoonBit full-range 64-bit stores created")
}
