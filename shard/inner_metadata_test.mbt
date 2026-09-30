///|
test "shard inner metadata is a valid ordinary temporary array view" {
  let raw = "{\"zarr_format\":3,\"node_type\":\"array\",\"shape\":[9],\"data_type\":\"uint8\",\"chunk_grid\":{\"name\":\"regular\",\"configuration\":{\"chunk_shape\":[8]}},\"chunk_key_encoding\":{\"name\":\"default\",\"configuration\":{\"separator\":\"/\"}},\"fill_value\":5,\"codecs\":[{\"name\":\"sharding_indexed\",\"configuration\":{\"chunk_shape\":[2],\"codecs\":[{\"name\":\"bytes\"}],\"index_codecs\":[{\"name\":\"bytes\"}],\"index_location\":\"end\"}}],\"attributes\":{\"source\":\"test\"}}"
  guard @shard.inner_metadata_json(raw) is Some(view_raw) else {
    fail("inner view")
  }
  guard @metadata.parse_array_metadata(view_raw) is Some(view) else {
    fail("inner parse")
  }
  assert_eq(view.shape, [9])
  assert_eq(view.chunk_shape, [2])
  assert_true(view.sharding is None)
  assert_eq(view.codecs.length(), 1)
  assert_true(view_raw.contains("source"))
}
