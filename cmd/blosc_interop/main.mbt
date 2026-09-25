///|
/// Generate new, non-overwriting Blosc stores for independent zarr-python
/// verification of LZ4 frames in both Zarr formats.
async fn main {
  let base = "integration/.roundtrip"
  let values : Array[UInt16] = []
  for i in 0..<4096 {
    values.push((i % 64).to_uint16())
  }
  for
    (name, format, shuffle) in [
      ("v2_blosc_lz4_shuffle_u16", @metadata.V2, 1),
      ("v3_blosc_lz4_bitshuffle_u16", @metadata.V3, 2),
      ("v3_blosc_lz4_noshuffle_u16", @metadata.V3, 0),
    ] {
    guard @fs.FileStore::new("\{base}/\{name}.zarr") is Some(store) else {
      fail("invalid Blosc output path")
    }
    guard store.create_u16(
        format,
        "",
        [4096],
        [4096],
        (0 : UInt16),
        compression=@codec.BloscLz4(5, shuffle, 2),
      )
      is Some(array) else {
      fail("Blosc array creation failed")
    }
    if !array.write_region([0], [4096], values) {
      fail("Blosc array write failed")
    }
    guard store.open_u16("") is Some(reopened) else {
      fail("Blosc reopen failed")
    }
    if reopened.read([63]) != Some((63 : UInt16)) ||
      reopened.read([4095]) != Some((63 : UInt16)) {
      fail("Blosc reread failed")
    }
  }
  guard @fs.FileStore::new("\{base}/v2_blosc_lz4_memcpy_u8.zarr") is Some(store) else {
    fail("invalid Blosc memcpy path")
  }
  guard store.create_u8(
      @metadata.V2,
      "",
      [5],
      [5],
      b'\x00',
      compression=@codec.BloscLz4(5, 2, 1),
    )
    is Some(array) else {
    fail("Blosc memcpy array creation failed")
  }
  if !array.write_region([0], [5], b"abcde") {
    fail("Blosc memcpy array write failed")
  }
}
