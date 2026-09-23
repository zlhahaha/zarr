///|
async test "filesystem store persists v2 and v3 chunks" {
  let dir = @async_fs.tmpdir(prefix="zarr-moonbit-test")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  let v2 =
    #|{"zarr_format":2,"shape":[4],"chunks":[2],"dtype":"|u1","compressor":null,"fill_value":0,"order":"C","filters":null}
  let v3 =
    #|{"zarr_format":3,"node_type":"array","shape":[4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  assert_true(store.put_array_metadata(@metadata.V2, "old", v2))
  assert_true(store.put_array_metadata(@metadata.V3, "new", v3))
  guard store.open_array("old") is Some(old) else { fail("v2") }
  guard store.open_array("new") is Some(new) else { fail("v3") }
  assert_true(store.put_chunk(old, [1], "old", b"\x01\x02"))
  assert_true(store.put_chunk(new, [1], "new", b"\x03\x04"))
  assert_eq(store.get_chunk(old, [1], "old"), Some(b"\x01\x02"))
  assert_eq(store.get_chunk(new, [1], "new"), Some(b"\x03\x04"))
  assert_true(!store.put("../escape", b"no"))
  assert_true(!store.put("dir/file:stream", b"no"))
  assert_true(!store.put("CON/zarr.json", b"no"))
  assert_true(!store.put("aux.txt", b"no"))
  assert_true(!store.put("trailing./zarr.json", b"no"))
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "native uint8 element writes persist after reopening" {
  let dir = @async_fs.tmpdir(prefix="zarr-u8-test")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  let raw =
    #|{"zarr_format":3,"node_type":"array","shape":[3],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":4,"codecs":[{"name":"bytes"}]}
  assert_true(store.put_array_metadata(@metadata.V3, "values", raw))
  guard store.open_u8("values") is Some(array) else { fail("array") }
  assert_eq(array.read([2]), Some(b'\x04'))
  assert_true(array.write([2], b'\x15'))
  guard @fs.FileStore::new(dir) is Some(reopened) else { fail("reopen store") }
  guard reopened.open_u8("values") is Some(saved) else { fail("reopen array") }
  assert_eq(saved.read([2]), Some(b'\x15'))
  assert_eq(reopened.get("values/c/1"), Some(b"\x15\x04"))
  assert_eq(saved.read([3]), None)
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "native float64 little-endian writes persist after reopening" {
  let dir = @async_fs.tmpdir(prefix="zarr-f64-test")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  let raw =
    #|{"zarr_format":3,"node_type":"array","shape":[3],"data_type":"float64","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":1.5,"codecs":[{"name":"bytes","configuration":{"endian":"little"}}]}
  assert_true(store.put_array_metadata(@metadata.V3, "values", raw))
  guard store.open_f64("values") is Some(array) else { fail("array") }
  assert_eq(array.read([2]), Some(1.5))
  assert_true(array.write([2], 42.25))
  guard @fs.FileStore::new(dir) is Some(reopened) else { fail("reopen store") }
  guard reopened.open_f64("values") is Some(saved) else { fail("reopen array") }
  assert_eq(saved.read([2]), Some(42.25))
  assert_eq(saved.read([1]), Some(1.5))
  assert_eq(
    reopened.get("values/c/1").map(fn(bytes) { bytes.length() }),
    Some(16),
  )
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "native store opens v2 and v3 group metadata" {
  let dir = @async_fs.tmpdir(prefix="zarr-group-test")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  assert_true(
    store.put_group_metadata(@metadata.V2, "legacy", "{\"zarr_format\":2}"),
  )
  assert_true(
    store.put_group_metadata(
      @metadata.V3,
      "modern",
      "{\"zarr_format\":3,\"node_type\":\"group\",\"attributes\":{\"title\":\"sample\"}}",
    ),
  )
  assert_true(store.put("legacy/.zattrs", b"{\"title\":\"old\"}"))
  guard store.open_group("legacy") is Some(v2) else { fail("v2 group") }
  guard store.open_group("modern") is Some(v3) else { fail("v3 group") }
  assert_eq(v2.attributes, @json.parse("{\"title\":\"old\"}"))
  assert_eq(v3.attributes, @json.parse("{\"title\":\"sample\"}"))
  assert_true(
    store.put_attributes(@metadata.V2, "legacy", "{\"title\":\"updated\"}"),
  )
  assert_true(
    store.put_attributes(@metadata.V3, "modern", "{\"title\":\"new\"}"),
  )
  assert_eq(
    store.read_attributes(@metadata.V2, "legacy"),
    Some(@json.parse("{\"title\":\"updated\"}")),
  )
  assert_eq(
    store.read_attributes(@metadata.V3, "modern"),
    Some(@json.parse("{\"title\":\"new\"}")),
  )
  assert_true(store.open_array("modern") is None)
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "native typed creation writes persistent v2 and v3 arrays" {
  let dir = @async_fs.tmpdir(prefix="zarr-create-test")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  guard store.create_u8(@metadata.V3, "image", [3], [2], b'\x05') is Some(image) else {
    fail("create u8")
  }
  assert_true(image.write([2], b'\x09'))
  assert_true(store.create_u8(@metadata.V3, "image", [3], [2], b'\x00') is None)
  guard store.create_f64(@metadata.V2, "signal", [2], [2], 1.5, big_endian=true)
    is Some(signal) else {
    fail("create f64")
  }
  assert_true(signal.write([1], 2.5))
  guard @fs.FileStore::new(dir) is Some(saved) else { fail("saved store") }
  guard saved.open_f64("signal") is Some(saved_signal) else {
    fail("saved f64")
  }
  assert_eq(saved_signal.read([1]), Some(2.5))
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "native float32 writes persist with big endian" {
  let dir = @async_fs.tmpdir(prefix="zarr-f32-test")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  guard store.create_f32(@metadata.V3, "signal", [2], [2], 1.5, big_endian=true)
    is Some(array) else {
    fail("create f32")
  }
  assert_true(array.write([0], 2.5))
  assert_eq(store.get("signal/c/0"), Some(b"\x40\x20\x00\x00\x3f\xc0\x00\x00"))
  guard @fs.FileStore::new(dir) is Some(saved) else { fail("saved store") }
  guard saved.open_f32("signal") is Some(saved_array) else { fail("open f32") }
  assert_eq(saved_array.read([0]), Some(2.5))
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "native int32 signed values persist" {
  let dir = @async_fs.tmpdir(prefix="zarr-i32-test")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  guard store.create_i32(@metadata.V3, "labels", [2], [2], -1) is Some(array) else {
    fail("create i32")
  }
  assert_true(array.write([0], -200))
  guard @fs.FileStore::new(dir) is Some(saved) else { fail("saved store") }
  guard saved.open_i32("labels") is Some(saved_array) else { fail("open i32") }
  assert_eq(saved_array.read([0]), Some(-200))
  assert_eq(saved_array.read([1]), Some(-1))
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "read independent zarr-python 3.4.0 v2 and v3 fixtures" {
  let base = "integration/fixtures/zarr-python"
  guard @fs.FileStore::new("\{base}/v2_u8.zarr") is Some(v2_u8_store) else {
    fail("v2 u8 store")
  }
  guard v2_u8_store.open_u8("") is Some(v2_u8) else { fail("v2 u8") }
  assert_eq(v2_u8.read([0, 0]), Some(b'\x05'))
  assert_eq(v2_u8.read([1, 2]), Some(b'\x07'))
  assert_eq(v2_u8.read([2, 3]), Some(b'\x09'))

  guard @fs.FileStore::new("\{base}/v3_u8.zarr") is Some(v3_u8_store) else {
    fail("v3 u8 store")
  }
  guard v3_u8_store.open_u8("") is Some(v3_u8) else { fail("v3 u8") }
  assert_eq(v3_u8.read([0, 0]), Some(b'\x05'))
  assert_eq(v3_u8.read([1, 2]), Some(b'\x07'))
  assert_eq(v3_u8.read([2, 3]), Some(b'\x09'))

  guard @fs.FileStore::new("\{base}/v2_f64_be.zarr") is Some(v2_f64_store) else {
    fail("v2 f64 store")
  }
  guard v2_f64_store.open_f64("") is Some(v2_f64) else { fail("v2 f64") }
  assert_eq(v2_f64.read([0]), Some(1.5))
  assert_eq(v2_f64.read([2]), Some(42.25))

  guard @fs.FileStore::new("\{base}/v3_f32_le.zarr") is Some(v3_f32_store) else {
    fail("v3 f32 store")
  }
  guard v3_f32_store.open_f32("") is Some(v3_f32) else { fail("v3 f32") }
  assert_eq(v3_f32.read([0]), Some(1.5))
  assert_eq(v3_f32.read([2]), Some(42.25))

  guard @fs.FileStore::new("\{base}/v3_i32_be.zarr") is Some(v3_i32_store) else {
    fail("v3 i32 store")
  }
  guard v3_i32_store.open_i32("") is Some(v3_i32) else { fail("v3 i32") }
  assert_eq(v3_i32.read([0]), Some(-1))
  assert_eq(v3_i32.read([2]), Some(-200))
}

///|
async test "native rectangular slices cross chunks for all supported dtypes" {
  let dir = @async_fs.tmpdir(prefix="zarr-slices-test")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  guard store.create_u8(@metadata.V3, "image", [3, 4], [2, 2], b'\x00')
    is Some(image) else {
    fail("image")
  }
  assert_true(image.write_region([1, 1], [2, 3], b"\x01\x02\x03\x04\x05\x06"))
  assert_eq(
    image.read_region([1, 1], [2, 3]),
    Some(b"\x01\x02\x03\x04\x05\x06"),
  )
  assert_eq(image.read_region([3, 0], [0, 4]), Some(b""))
  assert_eq(image.read_region([2, 3], [2, 1]), None)
  assert_true(!image.write_region([0, 0], [2, 2], b"\x01"))

  guard store.create_f32(@metadata.V3, "f32", [3], [2], 1.5) is Some(f32) else {
    fail("f32")
  }
  assert_true(f32.write_region([1], [2], [2.5, 3.5]))
  assert_eq(f32.read_region([0], [3]), Some([1.5, 2.5, 3.5]))

  guard store.create_f64(@metadata.V2, "f64", [3], [2], 1.5) is Some(f64) else {
    fail("f64")
  }
  assert_true(f64.write_region([1], [2], [2.5, 3.5]))
  assert_eq(f64.read_region([0], [3]), Some([1.5, 2.5, 3.5]))

  guard store.create_i32(@metadata.V3, "i32", [3], [2], -1) is Some(i32) else {
    fail("i32")
  }
  assert_true(i32.write_region([1], [2], [2, -3]))
  assert_eq(i32.read_region([0], [3]), Some([-1, 2, -3]))

  guard @fs.FileStore::new(dir) is Some(saved) else { fail("saved") }
  guard saved.open_u8("image") is Some(saved_image) else { fail("saved image") }
  assert_eq(
    saved_image.read_region([1, 1], [2, 3]),
    Some(b"\x01\x02\x03\x04\x05\x06"),
  )
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "read independent zarr-python compressed fixtures" {
  let base = "integration/fixtures/zarr-python"
  guard @fs.FileStore::new("\{base}/v2_gzip_u8.zarr") is Some(gzip_store) else {
    fail("gzip store")
  }
  guard gzip_store.open_u8("") is Some(gzip) else { fail("gzip array") }
  assert_eq(gzip.read([0]), Some(b'\x05'))
  assert_eq(gzip.read([2]), Some(b'\x09'))

  guard @fs.FileStore::new("\{base}/v2_zlib_f64.zarr") is Some(zlib_store) else {
    fail("zlib store")
  }
  guard zlib_store.open_f64("") is Some(zlib) else { fail("zlib array") }
  assert_eq(zlib.read([0]), Some(1.5))
  assert_eq(zlib.read([2]), Some(42.25))

  guard @fs.FileStore::new("\{base}/v3_gzip_i32.zarr") is Some(v3_store) else {
    fail("v3 gzip store")
  }
  guard v3_store.open_i32("") is Some(v3) else { fail("v3 gzip array") }
  assert_eq(v3.read([0]), Some(-1))
  assert_eq(v3.read([2]), Some(-200))
}

///|
async test "read independent zarr-python zstd fixtures" {
  let base = "integration/fixtures/zarr-python"
  guard @fs.FileStore::new("\{base}/v2_zstd_u8.zarr") is Some(v2_store) else {
    fail("v2 zstd store")
  }
  guard v2_store.open_u8("") is Some(v2) else { fail("v2 zstd array") }
  assert_eq(v2.read([0]), Some(b'\x05'))
  assert_eq(v2.read([2]), Some(b'\x09'))

  guard @fs.FileStore::new("\{base}/v3_zstd_f32.zarr") is Some(v3_store) else {
    fail("v3 zstd store")
  }
  guard v3_store.open_f32("") is Some(v3) else { fail("v3 zstd array") }
  assert_eq(v3.read([0]), Some(1.5))
  assert_eq(v3.read([2]), Some(42.25))
}

///|
async test "native compressed regions span chunks and persist" {
  let dir = @async_fs.tmpdir(prefix="zarr-compressed-region-test")
  guard @fs.FileStore::new(dir) is Some(store) else { fail("store") }
  guard store.create_u8(
      @metadata.V3,
      "image",
      [3, 4],
      [2, 2],
      b'\x05',
      compression=@codec.Zstd(3),
    )
    is Some(image) else {
    fail("image")
  }
  assert_true(image.write_region([1, 1], [2, 3], b"\x01\x02\x03\x04\x05\x06"))
  assert_eq(
    image.read_region([1, 1], [2, 3]),
    Some(b"\x01\x02\x03\x04\x05\x06"),
  )

  guard store.create_f32(
      @metadata.V3,
      "signal",
      [3],
      [2],
      1.5,
      compression=@codec.Gzip(1),
    )
    is Some(signal) else {
    fail("signal")
  }
  assert_true(signal.write_region([1], [2], [2.5, 42.25]))
  guard @fs.FileStore::new(dir) is Some(reopened) else { fail("reopened") }
  guard reopened.open_u8("image") is Some(saved_image) else {
    fail("saved image")
  }
  assert_eq(
    saved_image.read_region([1, 1], [2, 3]),
    Some(b"\x01\x02\x03\x04\x05\x06"),
  )
  guard reopened.open_f32("signal") is Some(saved_signal) else {
    fail("saved signal")
  }
  assert_eq(saved_signal.read_region([0], [3]), Some([1.5, 2.5, 42.25]))
  @async_fs.rmdir(dir, recursive=true)
}
