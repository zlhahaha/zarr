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
