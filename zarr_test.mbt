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

///|
test "v2 uint8 element read write, fill, and F order" {
  let store = @zarr.MemoryStore::new()
  let raw =
    #|{"zarr_format":2,"shape":[3,3],"chunks":[2,2],"dtype":"|u1","compressor":null,"fill_value":9,"order":"F","filters":null}
  assert_true(store.put_array_metadata(@zarr.V2, "matrix", raw))
  guard store.open_u8("matrix") is Some(array) else { fail("open_u8") }
  assert_eq(array.read([2, 2]), Some(b'\x09'))
  assert_true(array.write([0, 1], b'\x07'))
  assert_eq(array.read([0, 1]), Some(b'\x07'))
  assert_eq(array.read([1, 0]), Some(b'\x09'))
  guard store.open_array("matrix") is Some(metadata) else { fail("metadata") }
  assert_eq(
    store.get_chunk(metadata, [0, 0], "matrix"),
    Some(b"\x09\x09\x07\x09"),
  )
  assert_eq(array.read([3, 0]), None)
  assert_true(!array.write([3, 0], b'\x01'))
}

///|
test "v3 uint8 edge chunk materializes full chunk" {
  let store = @zarr.MemoryStore::new()
  let raw =
    #|{"zarr_format":3,"node_type":"array","shape":[3],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":5,"codecs":[{"name":"bytes"}]}
  assert_true(store.put_array_metadata(@zarr.V3, "edge", raw))
  guard store.open_u8("edge") is Some(array) else { fail("open_u8") }
  assert_eq(array.read([2]), Some(b'\x05'))
  assert_true(array.write([2], b'\x11'))
  assert_eq(array.read([2]), Some(b'\x11'))
  guard store.open_array("edge") is Some(metadata) else { fail("metadata") }
  assert_eq(store.get_chunk(metadata, [1], "edge"), Some(b"\x11\x05"))
}

///|
test "u8 array rejects unsupported codecs and corrupt chunks" {
  let store = @zarr.MemoryStore::new()
  let compressed =
    #|{"zarr_format":3,"node_type":"array","shape":[2],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"},{"name":"zstd"}]}
  assert_true(store.put_array_metadata(@zarr.V3, "compressed", compressed))
  assert_true(store.open_u8("compressed") is None)
  let plain =
    #|{"zarr_format":3,"node_type":"array","shape":[2],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  assert_true(store.put_array_metadata(@zarr.V3, "plain", plain))
  guard store.open_u8("plain") is Some(array) else { fail("open_u8") }
  store.put("plain/c/0", b"\x01")
  assert_eq(array.read([0]), None)
  assert_true(!array.write([0], b'\x02'))
}

///|
test "uint8 rectangular read crosses chunks in C output order" {
  let store = @zarr.MemoryStore::new()
  let raw =
    #|{"zarr_format":3,"node_type":"array","shape":[3,4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2,2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  assert_true(store.put_array_metadata(@zarr.V3, "image", raw))
  guard store.open_u8("image") is Some(array) else { fail("open_u8") }
  assert_true(array.write([1, 2], b'\x07'))
  assert_true(array.write([2, 3], b'\x08'))
  assert_eq(
    array.read_region([1, 1], [2, 3]),
    Some(b"\x00\x07\x00\x00\x00\x08"),
  )
  assert_eq(array.read_region([3, 0], [0, 4]), Some(b""))
  assert_eq(array.read_region([2, 3], [2, 1]), None)
  assert_eq(array.read_region([1], [2]), None)
  assert_true(array.write_region([0, 1], [2, 2], b"\x01\x02\x03\x04"))
  assert_eq(array.read_region([0, 1], [2, 2]), Some(b"\x01\x02\x03\x04"))
  assert_true(!array.write_region([0, 0], [2, 2], b"\x01"))
}

///|
test "scalar uint8 array uses c chunk key and one value" {
  let store = @zarr.MemoryStore::new()
  let raw =
    #|{"zarr_format":3,"node_type":"array","shape":[],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[]}},"chunk_key_encoding":{"name":"default"},"fill_value":6,"codecs":[{"name":"bytes"}]}
  assert_true(store.put_array_metadata(@zarr.V3, "scalar", raw))
  guard store.open_u8("scalar") is Some(array) else { fail("open_u8") }
  assert_eq(array.read([]), Some(b'\x06'))
  assert_true(array.write([], b'\x0a'))
  assert_eq(array.read_region([], []), Some(b"\x0a"))
  assert_eq(store.get("scalar/c"), Some(b"\x0a"))
}

///|
test "v3 float64 little-endian values and edge fill" {
  let store = @zarr.MemoryStore::new()
  let raw =
    #|{"zarr_format":3,"node_type":"array","shape":[3],"data_type":"float64","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":1.5,"codecs":[{"name":"bytes","configuration":{"endian":"little"}}]}
  assert_true(store.put_array_metadata(@zarr.V3, "science", raw))
  guard store.open_f64("science") is Some(array) else { fail("open_f64") }
  assert_eq(array.read([2]), Some(1.5))
  assert_true(array.write([2], 42.25))
  assert_eq(array.read([2]), Some(42.25))
  assert_eq(array.read([3]), None)
  assert_eq(array.read_region([1], [2]), Some([1.5, 42.25]))
  assert_true(array.write_region([0], [2], [3.0, 4.0]))
  assert_eq(array.read_region([0], [3]), Some([3.0, 4.0, 42.25]))
  assert_true(!array.write_region([0], [2], [1.0]))
  assert_eq(
    store.get("science/c/1"),
    Some(b"\x00\x00\x00\x00\x00\x20\x45\x40\x00\x00\x00\x00\x00\x00\xf8\x3f"),
  )
}

///|
test "v2 float64 big-endian F-order and unsupported endian" {
  let store = @zarr.MemoryStore::new()
  let raw =
    #|{"zarr_format":2,"shape":[2,2],"chunks":[2,2],"dtype":">f8","compressor":null,"fill_value":0,"order":"F","filters":null}
  assert_true(store.put_array_metadata(@zarr.V2, "matrix", raw))
  guard store.open_f64("matrix") is Some(array) else { fail("open_f64") }
  assert_true(array.write([0, 1], 2.5))
  assert_eq(array.read([0, 1]), Some(2.5))
  assert_eq(array.read([1, 0]), Some(0.0))
  guard store.get("matrix/0.0") is Some(chunk) else { fail("missing chunk") }
  assert_eq(chunk.length(), 32)
  assert_eq(chunk[16], b'\x40')
  assert_eq(chunk[17], b'\x04')
  let invalid =
    #|{"zarr_format":3,"node_type":"array","shape":[1],"data_type":"float64","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[1]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  assert_true(store.put_array_metadata(@zarr.V3, "invalid", invalid))
  assert_true(store.open_f64("invalid") is None)
}

///|
test "v2 and v3 groups keep attributes in their respective metadata" {
  let store = @zarr.MemoryStore::new()
  assert_true(store.put_group_metadata(@zarr.V2, "old", "{\"zarr_format\":2}"))
  assert_true(
    store.put_group_metadata(
      @zarr.V3,
      "new",
      "{\"zarr_format\":3,\"node_type\":\"group\",\"attributes\":{\"unit\":\"m\"}}",
    ),
  )
  store.put("old/.zattrs", b"{\"unit\":\"s\"}")
  guard store.open_group("old") is Some(old) else { fail("v2 group") }
  guard store.open_group("new") is Some(new) else { fail("v3 group") }
  assert_eq(old.format, @zarr.V2)
  assert_eq(new.format, @zarr.V3)
  assert_eq(old.attributes, @json.parse("{\"unit\":\"s\"}"))
  assert_eq(new.attributes, @json.parse("{\"unit\":\"m\"}"))
  assert_true(store.put_attributes(@zarr.V2, "old", "{\"unit\":\"kg\"}"))
  assert_true(store.put_attributes(@zarr.V3, "new", "{\"unit\":\"km\"}"))
  assert_eq(
    store.read_attributes(@zarr.V2, "old"),
    Some(@json.parse("{\"unit\":\"kg\"}")),
  )
  assert_eq(
    store.read_attributes(@zarr.V3, "new"),
    Some(@json.parse("{\"unit\":\"km\"}")),
  )
  assert_eq(store.get("old/.zgroup"), Some(b"{\"zarr_format\":2}"))
  assert_true(store.get("new/.zattrs") is None)
  assert_true(store.open_array("new") is None)
}

///|
test "groups reject mixed formats invalid attributes and v2 array collision" {
  let store = @zarr.MemoryStore::new()
  assert_true(
    !store.put_group_metadata(
      @zarr.V3,
      "bad",
      "{\"zarr_format\":3,\"node_type\":\"group\",\"attributes\":[]}",
    ),
  )
  assert_true(
    store.put_group_metadata(@zarr.V2, "mixed", "{\"zarr_format\":2}"),
  )
  assert_true(
    store.put_group_metadata(
      @zarr.V3,
      "mixed",
      "{\"zarr_format\":3,\"node_type\":\"group\"}",
    ),
  )
  assert_true(store.open_group("mixed") is None)
  assert_true(
    store.put_group_metadata(@zarr.V2, "corrupt", "{\"zarr_format\":2}"),
  )
  store.put("corrupt/.zattrs", b"[]")
  assert_true(store.open_group("corrupt") is None)
  assert_eq(@zarr.group_metadata_key(@zarr.V3, "../escape"), None)
  assert_true(!store.put_attributes(@zarr.V2, "absent", "{}"))
  assert_true(!store.put_attributes(@zarr.V3, "mixed", "[]"))
  let array_raw =
    #|{"zarr_format":3,"node_type":"array","shape":[1],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[1]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  assert_true(!store.put_array_metadata(@zarr.V3, "mixed", array_raw))
  assert_true(store.put_array_metadata(@zarr.V3, "array", array_raw))
  assert_true(
    !store.put_group_metadata(
      @zarr.V3,
      "array",
      "{\"zarr_format\":3,\"node_type\":\"group\"}",
    ),
  )
}
