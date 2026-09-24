///|
test "v2 metadata rejects malformed dimensions and encoding fields" {
  let v2_0 =
    #|{"zarr_format":2,"shape":[-1],"chunks":[2],"dtype":"|u1","compressor":null,"fill_value":0,"order":"C","filters":null}
  let v2_1 =
    #|{"zarr_format":2,"shape":[2.5],"chunks":[2],"dtype":"|u1","compressor":null,"fill_value":0,"order":"C","filters":null}
  let v2_2 =
    #|{"zarr_format":2,"shape":[4],"chunks":[0],"dtype":"|u1","compressor":null,"fill_value":0,"order":"C","filters":null}
  let v2_3 =
    #|{"zarr_format":2,"shape":[4,4],"chunks":[2],"dtype":"|u1","compressor":null,"fill_value":0,"order":"C","filters":null}
  let v2_4 =
    #|{"zarr_format":2,"shape":[4],"chunks":[2],"dtype":"|u1","compressor":null,"fill_value":0,"order":"X","filters":null}
  let v2_5 =
    #|{"zarr_format":2,"shape":[4],"chunks":[2],"dtype":"|u1","compressor":null,"fill_value":0,"order":"C","filters":null,"dimension_separator":"-"}
  let v2_6 =
    #|{"zarr_format":2,"shape":[4],"chunks":[2],"dtype":"|u1","compressor":"gzip","fill_value":0,"order":"C","filters":null}
  let v2_7 =
    #|{"zarr_format":2,"shape":[4],"chunks":[2],"dtype":"|u1","compressor":null,"fill_value":0,"order":"C","filters":{}}
  for raw in [v2_0, v2_1, v2_2, v2_3, v2_4, v2_5, v2_6, v2_7] {
    assert_true(@metadata.parse_array_metadata(raw) is None)
  }
}

///|
test "v3 metadata rejects malformed grids and key encodings" {
  let v3_0 =
    #|{"zarr_format":3,"node_type":"group","shape":[4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  let v3_1 =
    #|{"zarr_format":3,"node_type":"array","shape":[4.5],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  let v3_2 =
    #|{"zarr_format":3,"node_type":"array","shape":[4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[0]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  let v3_3 =
    #|{"zarr_format":3,"node_type":"array","shape":[4,4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  let v3_4 =
    #|{"zarr_format":3,"node_type":"array","shape":[4],"data_type":"uint8","chunk_grid":{"name":"irregular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  let v3_5 =
    #|{"zarr_format":3,"node_type":"array","shape":[4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"custom"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  let v3_6 =
    #|{"zarr_format":3,"node_type":"array","shape":[4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default","configuration":{"separator":"-"}},"fill_value":0,"codecs":[{"name":"bytes"}]}
  let v3_7 =
    #|{"zarr_format":3,"node_type":"array","shape":[4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[]}
  for raw in [v3_0, v3_1, v3_2, v3_3, v3_4, v3_5, v3_6, v3_7] {
    assert_true(@metadata.parse_array_metadata(raw) is None)
  }
}

///|
test "v3 metadata requires complete grid and valid optional fields" {
  let no_chunk_shape =
    #|{"zarr_format":3,"node_type":"array","shape":[4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  let no_encoding =
    #|{"zarr_format":3,"node_type":"array","shape":[4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"fill_value":0,"codecs":[{"name":"bytes"}]}
  let no_encoding_name =
    #|{"zarr_format":3,"node_type":"array","shape":[4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{},"fill_value":0,"codecs":[{"name":"bytes"}]}
  let bad_separator_type =
    #|{"zarr_format":3,"node_type":"array","shape":[4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default","configuration":{"separator":7}},"fill_value":0,"codecs":[{"name":"bytes"}]}
  let bad_transformers_type =
    #|{"zarr_format":3,"node_type":"array","shape":[4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}],"storage_transformers":{}}
  let unknown_format =
    #|{"zarr_format":4,"node_type":"array","shape":[4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  for
    raw in [
      no_chunk_shape, no_encoding, no_encoding_name, bad_separator_type, bad_transformers_type,
      unknown_format,
    ] {
    assert_true(@metadata.parse_array_metadata(raw) is None)
  }
  let defaulted_separator =
    #|{"zarr_format":3,"node_type":"array","shape":[4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default","configuration":{}},"fill_value":0,"codecs":[{"name":"bytes"}]}
  guard @metadata.parse_array_metadata(defaulted_separator) is Some(metadata) else {
    fail("valid defaulted separator rejected")
  }
  assert_eq(metadata.separator, "/")
}

///|
test "attribute helpers reject malformed documents and v2 metadata" {
  let v2_group =
    #|{"zarr_format":2}
  let v2_array =
    #|{"zarr_format":2,"shape":[2],"chunks":[2],"dtype":"|u1","compressor":null,"fill_value":0,"order":"C","filters":null}
  let v3_group =
    #|{"zarr_format":3,"node_type":"group"}
  let v3_bad_attributes =
    #|{"zarr_format":3,"node_type":"group","attributes":[]}
  for raw in ["[]", "{", "{\"zarr_format\":4}", v3_bad_attributes] {
    assert_true(@metadata.parse_group_metadata(raw) is None)
  }
  for raw in [v2_group, v2_array, v3_bad_attributes] {
    assert_true(@metadata.v3_attributes(raw) is None)
    assert_true(@metadata.replace_v3_attributes(raw, "{}") is None)
  }
  assert_true(@metadata.v3_attributes(v3_group) is Some(_))
  assert_true(@metadata.replace_v3_attributes(v3_group, "[]") is None)
  assert_true(
    @metadata.replace_v3_attributes(v3_group, "{\"unit\":\"m\"}") is Some(_),
  )
}

///|
test "Blosc variants outside the supported read subset fail at open" {
  let store = @store.MemoryStore::new()
  let bitshuffle_v2 =
    #|{"zarr_format":2,"shape":[8],"chunks":[8],"dtype":"<u2","compressor":{"id":"blosc","cname":"lz4","clevel":5,"shuffle":2,"blocksize":0},"fill_value":0,"order":"C","filters":null}
  let blosclz_v2 =
    #|{"zarr_format":2,"shape":[8],"chunks":[8],"dtype":"<u2","compressor":{"id":"blosc","cname":"blosclz","clevel":5,"shuffle":1,"blocksize":0},"fill_value":0,"order":"C","filters":null}
  let bitshuffle_v3 =
    #|{"zarr_format":3,"node_type":"array","shape":[8],"data_type":"uint16","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[8]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes","configuration":{"endian":"little"}},{"name":"blosc","configuration":{"typesize":2,"cname":"lz4","clevel":5,"shuffle":"bitshuffle","blocksize":0}}]}
  assert_true(
    store.put_array_metadata(@metadata.V2, "bitshuffle", bitshuffle_v2),
  )
  assert_true(store.put_array_metadata(@metadata.V2, "blosclz", blosclz_v2))
  assert_true(store.put_array_metadata(@metadata.V3, "v3", bitshuffle_v3))
  assert_true(@array.open_u16(store, "bitshuffle") is None)
  assert_true(@array.open_u16(store, "blosclz") is None)
  assert_true(@array.open_u16(store, "v3") is None)
}
