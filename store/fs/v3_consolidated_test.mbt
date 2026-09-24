///|
async test "v3 consolidated snapshot reads without child metadata files" {
  let base = "integration/fixtures/zarr-python/v3_consolidated_grouped_u8.zarr"
  guard @fs.FileStore::new(base) is Some(source) else { fail("source") }
  guard source.get("zarr.json") is Some(index) else {
    fail("v3 consolidated index")
  }
  guard source.get("science/image/c/1") is Some(chunk) else {
    fail("v3 consolidated chunk")
  }
  let dir = @async_fs.tmpdir(prefix="zarr-v3-consolidated-test")
  guard @fs.FileStore::new(dir) is Some(plain) else { fail("plain") }
  assert_true(
    plain.put("zarr.json", b"{\"zarr_format\":3,\"node_type\":\"group\"}"),
  )
  assert_true(@fs.FileStore::open_consolidated_v3(dir) is None)
  assert_true(
    plain.put(
      "zarr.json", b"{\"zarr_format\":3,\"node_type\":\"group\",\"consolidated_metadata\":{\"kind\":\"inline\",\"must_understand\":true,\"metadata\":{}}}",
    ),
  )
  assert_true(@fs.FileStore::open_consolidated_v3(dir) is None)
  assert_true(
    plain.put(
      "zarr.json", b"{\"zarr_format\":3,\"node_type\":\"group\",\"consolidated_metadata\":{\"kind\":\"inline\",\"must_understand\":false,\"metadata\":{\"../evil\":{\"zarr_format\":3,\"node_type\":\"group\"}}}}",
    ),
  )
  assert_true(@fs.FileStore::open_consolidated_v3(dir) is None)
  assert_true(plain.put("zarr.json", index))
  assert_true(plain.put("science/image/c/1", chunk))
  assert_true(plain.open_array("science/image") is None)
  guard @fs.FileStore::open_consolidated_v3(dir) is Some(view) else {
    fail("v3 consolidated view")
  }
  guard view.open_group("") is Some(root) else { fail("root") }
  assert_true(root.format == @metadata.V3)
  guard view.open_group("science") is Some(group) else { fail("nested group") }
  assert_eq(group.attributes, @json.parse("{\"title\":\"consolidated-v3\"}"))
  guard view.open_u8("science/image") is Some(image) else {
    fail("nested array")
  }
  assert_eq(image.read_region([0], [3]), Some(b"\x05\x05\x09"))
  assert_true(plain.put("science/zarr.json", b"invalid"))
  assert_true(plain.put("science/image/zarr.json", b"invalid"))
  assert_eq(
    view.read_attributes(@metadata.V3, "science"),
    Some(@json.parse("{\"title\":\"consolidated-v3\"}")),
  )
  assert_eq(image.read([2]), Some(b'\x09'))
  assert_true(!image.write([0], b'\x08'))
  assert_true(!view.put("new-key", b"new"))
  assert_true(!view.put_attributes(@metadata.V3, "science", "{\"x\":1}"))
  @async_fs.rmdir(dir, recursive=true)
}
