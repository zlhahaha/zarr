///|
/// Generate MoonBit-owned stores for zarr-python to verify. This command
/// deliberately refuses to overwrite previous generated stores.
async fn main {
  let base = "integration/.roundtrip"
  guard @fs.FileStore::new("\{base}/v2_u8.zarr") is Some(v2_u8_store) else {
    println("invalid output path")
    return
  }
  guard v2_u8_store.create_u8(@metadata.V2, "", [3, 4], [2, 2], b'\x05')
    is Some(v2_u8) else {
    println("v2 uint8 creation failed")
    return
  }
  if !v2_u8.write([1, 2], b'\x07') || !v2_u8.write([2, 3], b'\x09') {
    println("v2 uint8 write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v3_u8.zarr") is Some(v3_u8_store) else {
    println("invalid output path")
    return
  }
  guard v3_u8_store.create_u8(@metadata.V3, "", [3, 4], [2, 2], b'\x05')
    is Some(v3_u8) else {
    println("v3 uint8 creation failed")
    return
  }
  if !v3_u8.write([1, 2], b'\x07') || !v3_u8.write([2, 3], b'\x09') {
    println("v3 uint8 write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v2_f64_be.zarr") is Some(f64_store) else {
    println("invalid output path")
    return
  }
  guard f64_store.create_f64(@metadata.V2, "", [3], [2], 1.5, big_endian=true)
    is Some(f64) else {
    println("v2 float64 creation failed")
    return
  }
  if !f64.write([2], 42.25) {
    println("v2 float64 write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v3_f32_le.zarr") is Some(f32_store) else {
    println("invalid output path")
    return
  }
  guard f32_store.create_f32(@metadata.V3, "", [3], [2], 1.5) is Some(f32) else {
    println("v3 float32 creation failed")
    return
  }
  if !f32.write([2], 42.25) {
    println("v3 float32 write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v3_i32_be.zarr") is Some(i32_store) else {
    println("invalid output path")
    return
  }
  guard i32_store.create_i32(@metadata.V3, "", [3], [2], -1, big_endian=true)
    is Some(i32) else {
    println("v3 int32 creation failed")
    return
  }
  if !i32.write([2], -200) {
    println("v3 int32 write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v2_gzip_u8.zarr") is Some(gzip_store) else {
    println("invalid gzip output path")
    return
  }
  guard gzip_store.create_u8(
      @metadata.V2,
      "",
      [3],
      [2],
      b'\x05',
      compression=@codec.Gzip(1),
    )
    is Some(gzip) else {
    println("v2 gzip creation failed")
    return
  }
  if !gzip.write([2], b'\x09') {
    println("v2 gzip write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v2_zlib_f64.zarr") is Some(zlib_store) else {
    println("invalid zlib output path")
    return
  }
  guard zlib_store.create_f64(
      @metadata.V2,
      "",
      [3],
      [2],
      1.5,
      big_endian=true,
      compression=@codec.Zlib(1),
    )
    is Some(zlib) else {
    println("v2 zlib creation failed")
    return
  }
  if !zlib.write([2], 42.25) {
    println("v2 zlib write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v3_gzip_i32.zarr") is Some(v3_gzip_store) else {
    println("invalid v3 gzip output path")
    return
  }
  guard v3_gzip_store.create_i32(
      @metadata.V3,
      "",
      [3],
      [2],
      -1,
      big_endian=true,
      compression=@codec.Gzip(1),
    )
    is Some(v3_gzip) else {
    println("v3 gzip creation failed")
    return
  }
  if !v3_gzip.write([2], -200) {
    println("v3 gzip write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v2_zstd_u8.zarr") is Some(v2_zstd_store) else {
    println("invalid v2 zstd output path")
    return
  }
  guard v2_zstd_store.create_u8(
      @metadata.V2,
      "",
      [3],
      [2],
      b'\x05',
      compression=@codec.Zstd(3),
    )
    is Some(v2_zstd) else {
    println("v2 zstd creation failed")
    return
  }
  if !v2_zstd.write([2], b'\x09') {
    println("v2 zstd write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v3_zstd_f32.zarr") is Some(v3_zstd_store) else {
    println("invalid v3 zstd output path")
    return
  }
  guard v3_zstd_store.create_f32(
      @metadata.V3,
      "",
      [3],
      [2],
      1.5,
      compression=@codec.Zstd(3),
    )
    is Some(v3_zstd) else {
    println("v3 zstd creation failed")
    return
  }
  if !v3_zstd.write([2], 42.25) {
    println("v3 zstd write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v3_zstd_image.zarr") is Some(image_store) else {
    println("invalid compressed image output path")
    return
  }
  guard image_store.create_u8(
      @metadata.V3,
      "",
      [3, 4],
      [2, 2],
      b'\x05',
      compression=@codec.Zstd(3),
    )
    is Some(image) else {
    println("compressed image creation failed")
    return
  }
  if !image.write_region([1, 1], [2, 3], b"\x01\x02\x03\x04\x05\x06") {
    println("compressed image slice write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v2_u16_be.zarr") is Some(v2_u16_store) else {
    println("invalid v2 uint16 output path")
    return
  }
  guard v2_u16_store.create_u16(
      @metadata.V2,
      "",
      [3],
      [2],
      (60000 : UInt16),
      big_endian=true,
    )
    is Some(v2_u16) else {
    println("v2 uint16 creation failed")
    return
  }
  if !v2_u16.write([2], (65530 : UInt16)) {
    println("v2 uint16 write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v3_u16_le_zstd.zarr") is Some(v3_u16_store) else {
    println("invalid v3 uint16 output path")
    return
  }
  guard v3_u16_store.create_u16(
      @metadata.V3,
      "",
      [3],
      [2],
      (60000 : UInt16),
      compression=@codec.Zstd(3),
    )
    is Some(v3_u16) else {
    println("v3 uint16 creation failed")
    return
  }
  if !v3_u16.write([2], (65530 : UInt16)) {
    println("v3 uint16 write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v2_i16_be.zarr") is Some(v2_i16_store) else {
    println("invalid v2 int16 output path")
    return
  }
  guard v2_i16_store.create_i16(
      @metadata.V2,
      "",
      [3],
      [2],
      (-1234 : Int16),
      big_endian=true,
    )
    is Some(v2_i16) else {
    println("v2 int16 creation failed")
    return
  }
  if !v2_i16.write([2], (-32768 : Int16)) {
    println("v2 int16 write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v3_i16_le_zstd.zarr") is Some(v3_i16_store) else {
    println("invalid v3 int16 output path")
    return
  }
  guard v3_i16_store.create_i16(
      @metadata.V3,
      "",
      [3],
      [2],
      (-1234 : Int16),
      compression=@codec.Zstd(3),
    )
    is Some(v3_i16) else {
    println("v3 int16 creation failed")
    return
  }
  if !v3_i16.write([2], (32767 : Int16)) {
    println("v3 int16 write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v2_u32_be.zarr") is Some(v2_u32_store) else {
    println("invalid v2 uint32 output path")
    return
  }
  guard v2_u32_store.create_u32(
      @metadata.V2,
      "",
      [3],
      [2],
      4000000000U,
      big_endian=true,
    )
    is Some(v2_u32) else {
    println("v2 uint32 creation failed")
    return
  }
  if !v2_u32.write([2], 4294967295U) {
    println("v2 uint32 write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v3_u32_le_zstd.zarr") is Some(v3_u32_store) else {
    println("invalid v3 uint32 output path")
    return
  }
  guard v3_u32_store.create_u32(
      @metadata.V3,
      "",
      [3],
      [2],
      4000000000U,
      compression=@codec.Zstd(3),
    )
    is Some(v3_u32) else {
    println("v3 uint32 creation failed")
    return
  }
  if !v3_u32.write([2], 4294967294U) {
    println("v3 uint32 write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v2_grouped_u8.zarr") is Some(v2_group_store) else {
    println("invalid v2 group output path")
    return
  }
  if !v2_group_store.create_group_tree(@metadata.V2, "science") ||
    !v2_group_store.put_attributes(
      @metadata.V2,
      "science",
      "{\"title\":\"v2\"}",
    ) {
    println("v2 group creation failed")
    return
  }
  guard v2_group_store.create_u8(
      @metadata.V2,
      "science/image",
      [3],
      [2],
      b'\x05',
    )
    is Some(v2_image) else {
    println("v2 nested array creation failed")
    return
  }
  if !v2_image.write([2], b'\x09') {
    println("v2 nested array write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v3_grouped_u8.zarr") is Some(v3_group_store) else {
    println("invalid v3 group output path")
    return
  }
  if !v3_group_store.create_group_tree(@metadata.V3, "science") ||
    !v3_group_store.put_attributes(
      @metadata.V3,
      "science",
      "{\"title\":\"v3\"}",
    ) {
    println("v3 group creation failed")
    return
  }
  guard v3_group_store.create_u8(
      @metadata.V3,
      "science/image",
      [3],
      [2],
      b'\x05',
    )
    is Some(v3_image) else {
    println("v3 nested array creation failed")
    return
  }
  if !v3_image.write([2], b'\x09') {
    println("v3 nested array write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v2_bool.zarr") is Some(v2_bool_store) else {
    println("invalid v2 boolean output path")
    return
  }
  guard v2_bool_store.create_bool(@metadata.V2, "", [3, 4], [2, 2], true)
    is Some(v2_bool) else {
    println("v2 boolean creation failed")
    return
  }
  if !v2_bool.write_region([1, 1], [2, 3], [
      false, true, false, true, false, true,
    ]) {
    println("v2 boolean slice write failed")
    return
  }

  guard @fs.FileStore::new("\{base}/v3_bool_zstd.zarr") is Some(v3_bool_store) else {
    println("invalid v3 boolean output path")
    return
  }
  guard v3_bool_store.create_bool(
      @metadata.V3,
      "",
      [3, 4],
      [2, 2],
      true,
      compression=@codec.Zstd(3),
    )
    is Some(v3_bool) else {
    println("v3 boolean creation failed")
    return
  }
  if !v3_bool.write_region([1, 1], [2, 3], [
      false, true, false, true, false, true,
    ]) {
    println("v3 boolean slice write failed")
    return
  }
  println("MoonBit interop stores created")
}
