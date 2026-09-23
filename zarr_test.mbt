///|
test "v2 array metadata and chunk keys" {
  let raw =
    #|{"zarr_format":2,"shape":[5,7],"chunks":[2,3],"dtype":"<i4","compressor":null,"fill_value":0,"order":"C","filters":null}
  guard @zarr.parse_array_metadata(raw) is Some(meta) else {
    fail("expected v2 metadata")
  }
  assert_true(meta.format == @zarr.V2)
  assert_eq(meta.shape, [5, 7])
  assert_eq(meta.chunk_shape, [2, 3])
  assert_eq(
    @zarr.array_metadata_key(@zarr.V2, "group/data"),
    Some("group/data/.zarray"),
  )
  assert_eq(@zarr.chunk_key(meta, [2, 2], "group/data"), Some("group/data/2.2"))
  assert_eq(@zarr.chunk_key(meta, [3, 0], "group/data"), None)
}

///|
test "v3 array metadata and default chunk keys" {
  let raw =
    #|{"zarr_format":3,"node_type":"array","shape":[5,7],"data_type":"int32","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2,3]}},"chunk_key_encoding":{"name":"default","configuration":{"separator":"/"}},"fill_value":0,"codecs":[{"name":"bytes","configuration":{"endian":"little"}}]}
  guard @zarr.parse_array_metadata(raw) is Some(meta) else {
    fail("expected v3 metadata")
  }
  assert_true(meta.format == @zarr.V3)
  assert_eq(
    @zarr.array_metadata_key(@zarr.V3, "group/data"),
    Some("group/data/zarr.json"),
  )
  assert_eq(
    @zarr.chunk_key(meta, [2, 2], "group/data"),
    Some("group/data/c/2/2"),
  )
  assert_eq(@zarr.chunk_key(meta, [2, 3], "group/data"), None)
}

///|
test "v3 v2-compatible key encoding and scalar" {
  let raw =
    #|{"zarr_format":3,"node_type":"array","shape":[],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[]}},"chunk_key_encoding":{"name":"v2"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  guard @zarr.parse_array_metadata(raw) is Some(meta) else {
    fail("expected scalar metadata")
  }
  assert_eq(@zarr.chunk_key(meta, [], ""), Some("0"))
}

///|
test "reject malformed grids and unsafe paths" {
  let bad =
    #|{"zarr_format":2,"shape":[5,7],"chunks":[0],"dtype":"<i4","compressor":null,"fill_value":0,"order":"C","filters":null}
  assert_true(@zarr.parse_array_metadata(bad) is None)
  assert_eq(@zarr.array_metadata_key(@zarr.V2, "foo/../bar"), None)
  assert_eq(@zarr.array_metadata_key(@zarr.V3, "foo/__hidden"), None)
  assert_eq(
    @zarr.array_metadata_key(@zarr.V3, "\\foo\\bar/"),
    Some("foo/bar/zarr.json"),
  )
}

///|
test "memory store round-trip for both metadata formats and raw chunks" {
  let store = @zarr.MemoryStore::new()
  let v2 =
    #|{"zarr_format":2,"shape":[4],"chunks":[2],"dtype":"|u1","compressor":null,"fill_value":0,"order":"C","filters":null}
  let v3 =
    #|{"zarr_format":3,"node_type":"array","shape":[4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  assert_true(store.put_array_metadata(@zarr.V2, "old", v2))
  assert_true(store.put_array_metadata(@zarr.V3, "new", v3))
  guard store.open_array("old") is Some(old_meta) else { fail("v2 missing") }
  guard store.open_array("new") is Some(new_meta) else { fail("v3 missing") }
  assert_true(store.put_chunk(old_meta, [1], "old", b"\x03\x04"))
  assert_true(store.put_chunk(new_meta, [1], "new", b"\x05\x06"))
  assert_eq(store.get_chunk(old_meta, [1], "old"), Some(b"\x03\x04"))
  assert_eq(store.get_chunk(new_meta, [1], "new"), Some(b"\x05\x06"))
  assert_eq(store.get_chunk(new_meta, [2], "new"), None)
  assert_true(!store.put_array_metadata(@zarr.V3, "bad", v2))
}

///|
test "ambiguous version path is not autodetected" {
  let store = @zarr.MemoryStore::new()
  let v2 =
    #|{"zarr_format":2,"shape":[1],"chunks":[1],"dtype":"|u1","compressor":null,"fill_value":0,"order":"C","filters":null}
  let v3 =
    #|{"zarr_format":3,"node_type":"array","shape":[1],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[1]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  assert_true(store.put_array_metadata(@zarr.V2, "mixed", v2))
  assert_true(store.put_array_metadata(@zarr.V3, "mixed", v3))
  assert_true(store.open_array("mixed") is None)
}
