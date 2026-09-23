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
  println("MoonBit interop stores created")
}
