///|
fn nd_u16(indices : Array[Int]) -> UInt16 {
  let x = indices[0]
  let y = indices[1]
  let z = indices[2]
  if x < 1 || y < 1 || y >= 4 || z < 1 {
    return (60000 : UInt16)
  }
  let bump = if x == 4 && y == 3 && z == 8 { 7 } else { 0 }
  (1000 * x + 100 * y + z + 1 + bump).to_uint16()
}

///|
fn nd_f32(indices : Array[Int]) -> Float {
  let t = indices[0]
  let y = indices[1]
  let z = indices[2]
  let c = indices[3]
  if t < 1 || y < 1 || y >= 3 || z < 1 || c < 1 {
    return -1.5
  }
  let bump = if t == 2 && y == 2 && z == 6 && c == 3 { 7 } else { 0 }
  Float::from_int(100 * t + 10 * y + z - 50 + bump) + Float::from_int(c) / 4.0
}

///|
async test "Python 3D uint16 C/F, endian, gzip/zstd, shards, missing and edge chunks" {
  for
    name in [
      "nd3_v2_raw_u16", "nd3_v2_f_gzip_be_u16", "nd3_v3_zstd_u16", "nd3_v3_shard_gzip_be_u16",
    ] {
    guard @fs.FileStore::new("integration/fixtures/zarr-python/\{name}.zarr")
      is Some(store) else {
      fail(name)
    }
    guard store.open_u16("") is Some(array) else { fail(name) }
    for
      box in [
        ([0, 0, 0], [5, 7, 9]),
        ([1, 2, 3], [4, 4, 6]),
        ([4, 3, 8], [1, 1, 1]),
        ([5, 0, 0], [0, 7, 9]),
      ] {
      let (origin, extent) = box
      guard array.read_region(origin, extent) is Some(values) else {
        fail(name)
      }
      assert_eq(values.length(), extent[0] * extent[1] * extent[2])
      for linear in 0..<values.length() {
        assert_eq(
          values[linear],
          nd_u16(@chunk.region_coords(origin, extent, linear)),
        )
      }
    }
    assert_eq(array.read([4, 3, 8]), Some((4316 : UInt16)))
    assert_eq(array.read_region([4, 0, 0], [2, 1, 1]), None)
    guard @fs.FileStore::new("integration/fixtures/zarr-python/\{name}.zarr")
      is Some(reopened) else {
      fail(name)
    }
    guard reopened.open_u16("") is Some(saved) else { fail(name) }
    assert_eq(saved.read([4, 6, 8]), Some((60000 : UInt16)))
  }
}

///|
async test "Python 4D float32 time-space-feature arrays, C/F and start-index shards" {
  for
    name in [
      "nd4_v2_gzip_f32", "nd4_v2_f_zlib_be_f32", "nd4_v3_raw_be_f32", "nd4_v3_shard_zstd_f32",
    ] {
    guard @fs.FileStore::new("integration/fixtures/zarr-python/\{name}.zarr")
      is Some(store) else {
      fail(name)
    }
    guard store.open_f32("") is Some(array) else { fail(name) }
    for
      box in [
        ([0, 0, 0, 0], [3, 5, 7, 4]),
        ([1, 2, 2, 1], [2, 3, 5, 3]),
        ([2, 2, 6, 3], [1, 1, 1, 1]),
        ([3, 0, 0, 0], [0, 5, 7, 4]),
      ] {
      let (origin, extent) = box
      guard array.read_region(origin, extent) is Some(values) else {
        fail(name)
      }
      assert_eq(values.length(), extent[0] * extent[1] * extent[2] * extent[3])
      for linear in 0..<values.length() {
        assert_eq(
          values[linear],
          nd_f32(@chunk.region_coords(origin, extent, linear)),
        )
      }
    }
    assert_eq(array.read([2, 2, 6, 3]), Some(183.75F))
    assert_eq(array.read_region([2, 0, 0, 0], [2, 1, 1, 1]), None)
    guard @fs.FileStore::new("integration/fixtures/zarr-python/\{name}.zarr")
      is Some(reopened) else {
      fail(name)
    }
    guard reopened.open_f32("") is Some(saved) else { fail(name) }
    assert_eq(saved.read([2, 4, 6, 3]), Some(-1.5F))
  }
}
