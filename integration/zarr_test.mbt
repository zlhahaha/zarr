///|
test "v2 array metadata and chunk keys" {
  let raw =
    #|{"zarr_format":2,"shape":[5,7],"chunks":[2,3],"dtype":"<i4","compressor":null,"fill_value":0,"order":"C","filters":null}
  guard @metadata.parse_array_metadata(raw) is Some(meta) else {
    fail("expected v2 metadata")
  }
  assert_true(meta.format == @metadata.V2)
  assert_eq(meta.shape, [5, 7])
  assert_eq(meta.chunk_shape, [2, 3])
  assert_eq(
    @chunk.array_metadata_key(@metadata.V2, "group/data"),
    Some("group/data/.zarray"),
  )
  assert_eq(
    @chunk.chunk_key(meta, [2, 2], "group/data"),
    Some("group/data/2.2"),
  )
  assert_eq(@chunk.chunk_key(meta, [3, 0], "group/data"), None)
}

///|
test "v3 array metadata and default chunk keys" {
  let raw =
    #|{"zarr_format":3,"node_type":"array","shape":[5,7],"data_type":"int32","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2,3]}},"chunk_key_encoding":{"name":"default","configuration":{"separator":"/"}},"fill_value":0,"codecs":[{"name":"bytes","configuration":{"endian":"little"}}]}
  guard @metadata.parse_array_metadata(raw) is Some(meta) else {
    fail("expected v3 metadata")
  }
  assert_true(meta.format == @metadata.V3)
  assert_eq(
    @chunk.array_metadata_key(@metadata.V3, "group/data"),
    Some("group/data/zarr.json"),
  )
  assert_eq(
    @chunk.chunk_key(meta, [2, 2], "group/data"),
    Some("group/data/c/2/2"),
  )
  assert_eq(@chunk.chunk_key(meta, [2, 3], "group/data"), None)
}

///|
test "v3 v2-compatible key encoding and scalar" {
  let raw =
    #|{"zarr_format":3,"node_type":"array","shape":[],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[]}},"chunk_key_encoding":{"name":"v2"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  guard @metadata.parse_array_metadata(raw) is Some(meta) else {
    fail("expected scalar metadata")
  }
  assert_eq(@chunk.chunk_key(meta, [], ""), Some("0"))
}

///|
test "reject malformed grids and unsafe paths" {
  let bad =
    #|{"zarr_format":2,"shape":[5,7],"chunks":[0],"dtype":"<i4","compressor":null,"fill_value":0,"order":"C","filters":null}
  assert_true(@metadata.parse_array_metadata(bad) is None)
  assert_eq(@chunk.array_metadata_key(@metadata.V2, "foo/../bar"), None)
  assert_eq(@chunk.array_metadata_key(@metadata.V3, "foo/__hidden"), None)
  assert_eq(
    @chunk.array_metadata_key(@metadata.V3, "\\foo\\bar/"),
    Some("foo/bar/zarr.json"),
  )
}

///|
test "memory store round-trip for both metadata formats and raw chunks" {
  let store = @store.MemoryStore::new()
  let v2 =
    #|{"zarr_format":2,"shape":[4],"chunks":[2],"dtype":"|u1","compressor":null,"fill_value":0,"order":"C","filters":null}
  let v3 =
    #|{"zarr_format":3,"node_type":"array","shape":[4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  assert_true(store.put_array_metadata(@metadata.V2, "old", v2))
  assert_true(store.put_array_metadata(@metadata.V3, "new", v3))
  guard store.open_array("old") is Some(old_meta) else { fail("v2 missing") }
  guard store.open_array("new") is Some(new_meta) else { fail("v3 missing") }
  assert_true(store.put_chunk(old_meta, [1], "old", b"\x03\x04"))
  assert_true(store.put_chunk(new_meta, [1], "new", b"\x05\x06"))
  assert_eq(store.get_chunk(old_meta, [1], "old"), Some(b"\x03\x04"))
  assert_eq(store.get_chunk(new_meta, [1], "new"), Some(b"\x05\x06"))
  assert_eq(store.get_chunk(new_meta, [2], "new"), None)
  assert_true(!store.put_array_metadata(@metadata.V3, "bad", v2))
}

///|
test "ambiguous version path is not autodetected" {
  let store = @store.MemoryStore::new()
  let v2 =
    #|{"zarr_format":2,"shape":[1],"chunks":[1],"dtype":"|u1","compressor":null,"fill_value":0,"order":"C","filters":null}
  let v3 =
    #|{"zarr_format":3,"node_type":"array","shape":[1],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[1]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  assert_true(store.put_array_metadata(@metadata.V2, "mixed", v2))
  assert_true(store.put_array_metadata(@metadata.V3, "mixed", v3))
  assert_true(store.open_array("mixed") is None)
}

///|
test "v2 uint8 element read write, fill, and F order" {
  let store = @store.MemoryStore::new()
  let raw =
    #|{"zarr_format":2,"shape":[3,3],"chunks":[2,2],"dtype":"|u1","compressor":null,"fill_value":9,"order":"F","filters":null}
  assert_true(store.put_array_metadata(@metadata.V2, "matrix", raw))
  guard @array.open_u8(store, "matrix") is Some(array) else { fail("open_u8") }
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
  let store = @store.MemoryStore::new()
  let raw =
    #|{"zarr_format":3,"node_type":"array","shape":[3],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":5,"codecs":[{"name":"bytes"}]}
  assert_true(store.put_array_metadata(@metadata.V3, "edge", raw))
  guard @array.open_u8(store, "edge") is Some(array) else { fail("open_u8") }
  assert_eq(array.read([2]), Some(b'\x05'))
  assert_true(array.write([2], b'\x11'))
  assert_eq(array.read([2]), Some(b'\x11'))
  guard store.open_array("edge") is Some(metadata) else { fail("metadata") }
  assert_eq(store.get_chunk(metadata, [1], "edge"), Some(b"\x11\x05"))
}

///|
test "u8 array rejects unsupported codecs and corrupt chunks" {
  let store = @store.MemoryStore::new()
  let compressed =
    #|{"zarr_format":3,"node_type":"array","shape":[2],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"},{"name":"zstd"}]}
  assert_true(store.put_array_metadata(@metadata.V3, "compressed", compressed))
  assert_true(@array.open_u8(store, "compressed") is None)
  let plain =
    #|{"zarr_format":3,"node_type":"array","shape":[2],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  assert_true(store.put_array_metadata(@metadata.V3, "plain", plain))
  guard @array.open_u8(store, "plain") is Some(array) else { fail("open_u8") }
  store.put("plain/c/0", b"\x01")
  assert_eq(array.read([0]), None)
  assert_true(!array.write([0], b'\x02'))
}

///|
test "uint8 rectangular read crosses chunks in C output order" {
  let store = @store.MemoryStore::new()
  let raw =
    #|{"zarr_format":3,"node_type":"array","shape":[3,4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2,2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  assert_true(store.put_array_metadata(@metadata.V3, "image", raw))
  guard @array.open_u8(store, "image") is Some(array) else { fail("open_u8") }
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
  let store = @store.MemoryStore::new()
  let raw =
    #|{"zarr_format":3,"node_type":"array","shape":[],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[]}},"chunk_key_encoding":{"name":"default"},"fill_value":6,"codecs":[{"name":"bytes"}]}
  assert_true(store.put_array_metadata(@metadata.V3, "scalar", raw))
  guard @array.open_u8(store, "scalar") is Some(array) else { fail("open_u8") }
  assert_eq(array.read([]), Some(b'\x06'))
  assert_true(array.write([], b'\x0a'))
  assert_eq(array.read_region([], []), Some(b"\x0a"))
  assert_eq(store.get("scalar/c"), Some(b"\x0a"))
}

///|
test "v3 float64 little-endian values and edge fill" {
  let store = @store.MemoryStore::new()
  let raw =
    #|{"zarr_format":3,"node_type":"array","shape":[3],"data_type":"float64","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":1.5,"codecs":[{"name":"bytes","configuration":{"endian":"little"}}]}
  assert_true(store.put_array_metadata(@metadata.V3, "science", raw))
  guard @array.open_f64(store, "science") is Some(array) else {
    fail("open_f64")
  }
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
  let store = @store.MemoryStore::new()
  let raw =
    #|{"zarr_format":2,"shape":[2,2],"chunks":[2,2],"dtype":">f8","compressor":null,"fill_value":0,"order":"F","filters":null}
  assert_true(store.put_array_metadata(@metadata.V2, "matrix", raw))
  guard @array.open_f64(store, "matrix") is Some(array) else {
    fail("open_f64")
  }
  assert_true(array.write([0, 1], 2.5))
  assert_eq(array.read([0, 1]), Some(2.5))
  assert_eq(array.read([1, 0]), Some(0.0))
  guard store.get("matrix/0.0") is Some(chunk) else { fail("missing chunk") }
  assert_eq(chunk.length(), 32)
  assert_eq(chunk[16], b'\x40')
  assert_eq(chunk[17], b'\x04')
  let invalid =
    #|{"zarr_format":3,"node_type":"array","shape":[1],"data_type":"float64","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[1]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  assert_true(store.put_array_metadata(@metadata.V3, "invalid", invalid))
  assert_true(@array.open_f64(store, "invalid") is None)
}

///|
test "v2 and v3 groups keep attributes in their respective metadata" {
  let store = @store.MemoryStore::new()
  assert_true(
    @hierarchy.put_group_metadata(
      store,
      @metadata.V2,
      "old",
      "{\"zarr_format\":2}",
    ),
  )
  assert_true(
    @hierarchy.put_group_metadata(
      store,
      @metadata.V3,
      "new",
      "{\"zarr_format\":3,\"node_type\":\"group\",\"attributes\":{\"unit\":\"m\"}}",
    ),
  )
  store.put("old/.zattrs", b"{\"unit\":\"s\"}")
  guard @hierarchy.open_group(store, "old") is Some(old) else {
    fail("v2 group")
  }
  guard @hierarchy.open_group(store, "new") is Some(new) else {
    fail("v3 group")
  }
  assert_eq(old.format, @metadata.V2)
  assert_eq(new.format, @metadata.V3)
  assert_eq(old.attributes, @json.parse("{\"unit\":\"s\"}"))
  assert_eq(new.attributes, @json.parse("{\"unit\":\"m\"}"))
  assert_true(
    @hierarchy.put_attributes(store, @metadata.V2, "old", "{\"unit\":\"kg\"}"),
  )
  assert_true(
    @hierarchy.put_attributes(store, @metadata.V3, "new", "{\"unit\":\"km\"}"),
  )
  assert_eq(
    @hierarchy.read_attributes(store, @metadata.V2, "old"),
    Some(@json.parse("{\"unit\":\"kg\"}")),
  )
  assert_eq(
    @hierarchy.read_attributes(store, @metadata.V3, "new"),
    Some(@json.parse("{\"unit\":\"km\"}")),
  )
  assert_eq(store.get("old/.zgroup"), Some(b"{\"zarr_format\":2}"))
  assert_true(store.get("new/.zattrs") is None)
  assert_true(store.open_array("new") is None)
}

///|
test "groups reject mixed formats invalid attributes and v2 array collision" {
  let store = @store.MemoryStore::new()
  assert_true(
    !@hierarchy.put_group_metadata(
      store,
      @metadata.V3,
      "bad",
      "{\"zarr_format\":3,\"node_type\":\"group\",\"attributes\":[]}",
    ),
  )
  assert_true(
    @hierarchy.put_group_metadata(
      store,
      @metadata.V2,
      "mixed",
      "{\"zarr_format\":2}",
    ),
  )
  assert_true(
    @hierarchy.put_group_metadata(
      store,
      @metadata.V3,
      "mixed",
      "{\"zarr_format\":3,\"node_type\":\"group\"}",
    ),
  )
  assert_true(@hierarchy.open_group(store, "mixed") is None)
  assert_true(
    @hierarchy.put_group_metadata(
      store,
      @metadata.V2,
      "corrupt",
      "{\"zarr_format\":2}",
    ),
  )
  store.put("corrupt/.zattrs", b"[]")
  assert_true(@hierarchy.open_group(store, "corrupt") is None)
  assert_eq(@chunk.group_metadata_key(@metadata.V3, "../escape"), None)
  assert_true(!@hierarchy.put_attributes(store, @metadata.V2, "absent", "{}"))
  assert_true(!@hierarchy.put_attributes(store, @metadata.V3, "mixed", "[]"))
  let array_raw =
    #|{"zarr_format":3,"node_type":"array","shape":[1],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[1]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  assert_true(!store.put_array_metadata(@metadata.V3, "mixed", array_raw))
  assert_true(store.put_array_metadata(@metadata.V3, "array", array_raw))
  assert_true(
    !@hierarchy.put_group_metadata(
      store,
      @metadata.V3,
      "array",
      "{\"zarr_format\":3,\"node_type\":\"group\"}",
    ),
  )
}

///|
test "typed array creation validates dimensions and prevents overwrite" {
  let store = @store.MemoryStore::new()
  guard @array.create_u8(store, @metadata.V3, "image", [3, 4], [2, 2], b'\x06')
    is Some(image) else {
    fail("create u8")
  }
  assert_eq(image.read([2, 3]), Some(b'\x06'))
  assert_true(image.write([2, 3], b'\x09'))
  assert_true(
    @array.create_u8(store, @metadata.V3, "image", [3, 4], [2, 2], b'\x00')
    is None,
  )
  assert_true(
    @array.create_u8(store, @metadata.V2, "bad", [2], [0], b'\x00') is None,
  )
  guard @array.create_f64(
      store,
      @metadata.V2,
      "signal",
      [2],
      [2],
      1.5,
      big_endian=true,
    )
    is Some(signal) else {
    fail("create f64")
  }
  assert_eq(signal.read([1]), Some(1.5))
  assert_true(
    @array.create_f64(store, @metadata.V3, "signal", [2], [2], 0.0) is None,
  )
}

///|
test "float32 v2 and v3 round-trip with endian and slices" {
  let store = @store.MemoryStore::new()
  guard @array.create_f32(store, @metadata.V3, "f32", [3], [2], 1.5) is Some(v3) else {
    fail("create v3 float32")
  }
  assert_eq(v3.read([2]), Some(1.5))
  assert_true(v3.write_region([1], [2], [2.5, 42.25]))
  assert_eq(v3.read_region([0], [3]), Some([1.5, 2.5, 42.25]))
  assert_eq(store.get("f32/c/1"), Some(b"\x00\x00\x29\x42\x00\x00\xc0\x3f"))
  guard @array.create_f32(
      store,
      @metadata.V2,
      "big",
      [2],
      [2],
      1.5,
      big_endian=true,
    )
    is Some(v2) else {
    fail("create v2 float32")
  }
  assert_true(v2.write([0], 2.5))
  assert_eq(store.get("big/0"), Some(b"\x40\x20\x00\x00\x3f\xc0\x00\x00"))
  assert_eq(v2.read([0]), Some(2.5))
}

///|
test "int32 v2 and v3 round-trip signed values and chunk edges" {
  let store = @store.MemoryStore::new()
  guard @array.create_i32(store, @metadata.V3, "labels", [3], [2], -1)
    is Some(v3) else {
    fail("create v3 int32")
  }
  assert_eq(v3.read([2]), Some(-1))
  assert_true(v3.write_region([1], [2], [100, -200]))
  assert_eq(v3.read_region([0], [3]), Some([-1, 100, -200]))
  assert_eq(store.get("labels/c/1"), Some(b"\x38\xff\xff\xff\xff\xff\xff\xff"))
  guard @array.create_i32(
      store,
      @metadata.V2,
      "big",
      [2],
      [2],
      -1,
      big_endian=true,
    )
    is Some(v2) else {
    fail("create v2 int32")
  }
  assert_true(v2.write([0], 100))
  assert_eq(store.get("big/0"), Some(b"\x00\x00\x00\x64\xff\xff\xff\xff"))
  assert_eq(v2.read([1]), Some(-1))
}

///|
test "chunk region planning covers edge chunks and scalar arrays" {
  let raw =
    #|{"zarr_format":3,"node_type":"array","shape":[3,4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2,2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  guard @metadata.parse_array_metadata(raw) is Some(meta) else {
    fail("metadata")
  }
  guard @chunk.region_chunks(meta, [1, 1], [2, 3]) is Some(pieces) else {
    fail("region chunks")
  }
  assert_eq(pieces.length(), 4)
  assert_eq(pieces[0].coordinates, [0, 0])
  assert_eq(pieces[0].origin, [1, 1])
  assert_eq(pieces[0].extent, [1, 1])
  assert_eq(pieces[3].coordinates, [1, 1])
  assert_eq(pieces[3].origin, [2, 2])
  assert_eq(pieces[3].extent, [1, 2])
  assert_eq(@chunk.region_index([1, 1], [2, 3], [2, 3]), Some(5))
  assert_eq(@chunk.region_index([1, 1], [2, 3], [2, 4]), None)
  guard @chunk.region_chunks(meta, [3, 0], [0, 4]) is Some(empty) else {
    fail("empty region")
  }
  assert_eq(empty.length(), 0)
  assert_true(@chunk.region_chunks(meta, [2, 3], [2, 1]) is None)
  let scalar_raw =
    #|{"zarr_format":3,"node_type":"array","shape":[],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  guard @metadata.parse_array_metadata(scalar_raw) is Some(scalar) else {
    fail("scalar metadata")
  }
  guard @chunk.region_chunks(scalar, [], []) is Some(scalar_pieces) else {
    fail("scalar region")
  }
  assert_eq(scalar_pieces.length(), 1)
  assert_eq(scalar_pieces[0].coordinates, [])
}

///|
test "gzip and zlib chunks round-trip and reject invalid payloads" {
  let store = @store.MemoryStore::new()
  guard @array.create_u8(
      store,
      @metadata.V3,
      "gzip",
      [3],
      [2],
      b'\x05',
      compression=@codec.Gzip(1),
    )
    is Some(gzip) else {
    fail("create gzip array")
  }
  assert_true(gzip.write([2], b'\x09'))
  assert_eq(gzip.read([2]), Some(b'\x09'))
  guard store.get("gzip/c/1") is Some(compressed) else { fail("gzip chunk") }
  assert_true(compressed.length() > 2)
  assert_eq(compressed[0], b'\x1f')
  assert_eq(compressed[1], b'\x8b')
  store.put("gzip/c/1", b"broken")
  assert_eq(gzip.read([2]), None)
  assert_true(!gzip.write([2], b'\x01'))
  guard @codec.encode_chunk(@codec.Gzip(1), b"\x01\x02\x03") is Some(oversized) else {
    fail("encode gzip")
  }
  store.put("gzip/c/1", oversized)
  assert_eq(gzip.read([2]), None)
  guard @codec.encode_chunk(@codec.Gzip(1), b"\x01\x02") is Some(valid) else {
    fail("encode gzip")
  }
  store.put("gzip/c/1", valid + b"junk")
  assert_eq(gzip.read([2]), None)

  guard @array.create_f64(
      store,
      @metadata.V2,
      "zlib",
      [3],
      [2],
      1.5,
      compression=@codec.Zlib(1),
    )
    is Some(zlib) else {
    fail("create zlib array")
  }
  assert_true(zlib.write([2], 42.25))
  assert_eq(zlib.read([2]), Some(42.25))
  assert_true(
    @array.create_u8(
      store,
      @metadata.V3,
      "unsupported",
      [2],
      [2],
      b'\x00',
      compression=@codec.Zlib(1),
    )
    is None,
  )
  assert_true(
    @array.create_u8(
      store,
      @metadata.V2,
      "invalid",
      [2],
      [2],
      b'\x00',
      compression=@codec.Gzip(99),
    )
    is None,
  )
  let filtered =
    #|{"zarr_format":2,"shape":[2],"chunks":[2],"dtype":"|u1","compressor":null,"fill_value":0,"order":"C","filters":[{"id":"gzip","level":1}]}
  assert_true(store.put_array_metadata(@metadata.V2, "filtered", filtered))
  assert_true(@array.open_u8(store, "filtered") is None)
}

///|
test "zstd chunks round-trip with declared chunk bound" {
  let store = @store.MemoryStore::new()
  guard @array.create_u8(
      store,
      @metadata.V3,
      "zstd",
      [3],
      [2],
      b'\x05',
      compression=@codec.Zstd(3),
    )
    is Some(array) else {
    fail("create zstd array")
  }
  assert_true(array.write([2], b'\x09'))
  assert_eq(array.read([0]), Some(b'\x05'))
  assert_eq(array.read([2]), Some(b'\x09'))
  guard @codec.encode_chunk(@codec.Zstd(3), b"\x01\x02\x03") is Some(oversized) else {
    fail("encode oversized zstd")
  }
  store.put("zstd/c/1", oversized)
  assert_eq(array.read([2]), None)
  assert_true(!array.write([2], b'\x01'))

  let checksummed =
    #|{"zarr_format":3,"node_type":"array","shape":[2],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"},{"name":"zstd","configuration":{"level":3,"checksum":true}}]}
  assert_true(
    store.put_array_metadata(@metadata.V3, "checksummed", checksummed),
  )
  assert_true(@array.open_u8(store, "checksummed") is None)
}

///|
test "compressed regions process whole chunks across dtype and order" {
  let store = @store.MemoryStore::new()
  let f_order =
    #|{"zarr_format":2,"shape":[3,3],"chunks":[2,2],"dtype":"|u1","compressor":{"id":"gzip","level":1},"fill_value":5,"order":"F","filters":null}
  assert_true(store.put_array_metadata(@metadata.V2, "image", f_order))
  guard @array.open_u8(store, "image") is Some(image) else { fail("image") }
  assert_true(image.write_region([1, 1], [2, 2], b"\x01\x02\x03\x04"))
  assert_eq(
    image.read_region([0, 0], [3, 3]),
    Some(b"\x05\x05\x05\x05\x01\x02\x05\x03\x04"),
  )

  guard @array.create_f32(
      store,
      @metadata.V3,
      "f32",
      [3],
      [2],
      1.5,
      compression=@codec.Zstd(3),
    )
    is Some(f32) else {
    fail("f32")
  }
  assert_true(f32.write_region([1], [2], [2.5, 42.25]))
  assert_eq(f32.read_region([0], [3]), Some([1.5, 2.5, 42.25]))

  guard @array.create_f64(
      store,
      @metadata.V2,
      "f64",
      [3],
      [2],
      1.5,
      big_endian=true,
      compression=@codec.Zlib(1),
    )
    is Some(f64) else {
    fail("f64")
  }
  assert_true(f64.write_region([1], [2], [2.5, 42.25]))
  assert_eq(f64.read_region([0], [3]), Some([1.5, 2.5, 42.25]))

  guard @array.create_i32(
      store,
      @metadata.V3,
      "i32",
      [3],
      [2],
      -1,
      big_endian=true,
      compression=@codec.Gzip(1),
    )
    is Some(i32) else {
    fail("i32")
  }
  assert_true(i32.write_region([1], [2], [100, -200]))
  assert_eq(i32.read_region([0], [3]), Some([-1, 100, -200]))
}
