///|
async test "filesystem discovery follows metadata and respects snapshot indexes" {
  let directory = @async_fs.tmpdir(prefix="zarr-discovery")
  guard @fs.FileStore::new(directory) is Some(store) else { fail("store") }
  assert_true(store.create_group_tree(@metadata.V3, "z/deep"))
  guard store.create_u8(@metadata.V3, "a", [2], [1], b'\x00') is Some(array) else {
    fail("array")
  }
  assert_true(array.write([0], b'\x07'))
  @async_fs.mkdir("\{directory}/unmarked", recursive=true)
  assert_true(store.put("unmarked/note.txt", b"not a node"))
  let nodes = match store.walk_result("") {
    Ok(nodes) => nodes
    Err(_) => fail("walk")
  }
  assert_eq(nodes.map(node => node.path), ["a", "z", "z/deep"])
  assert_true(store.list_children_result("a") is Err(@store.NotGroup("a")))
  assert_true(
    store.walk_result("", max_nodes=2) is Err(@store.LimitExceeded(_, _)),
  )
  assert_true(
    store.walk_result("", max_depth=0) is Err(@store.LimitExceeded(_, _)),
  )
  assert_true(store.list_children_result("../") is Err(@store.InvalidPath(_)))
  assert_true(store.list_children_result("a:b") is Err(@store.InvalidPath(_)))
  guard @store.ReadLimits::new(max_metadata_bytes=4) is Some(limits) else {
    fail("limits")
  }
  guard @fs.FileStore::new(directory, read_limits=limits) is Some(limited) else {
    fail("limited store")
  }
  assert_true(
    limited.open_node_result("") is Err(@store.LimitExceeded("metadata", "")),
  )
  assert_true(
    store.list_children_result("", max_entries=1)
    is Err(@store.LimitExceeded(_, _)),
  )
  assert_true(store.put("z/zarr.json", b"bad"))
  assert_true(
    store.list_children_result("") is Err(@store.InvalidMetadata("z")),
  )
  @async_fs.rmdir(directory, recursive=true)
  guard @fs.FileStore::open_consolidated(
      "integration/fixtures/zarr-python/v2_consolidated_grouped_u8.zarr",
    )
    is Some(snapshot) else {
    fail("snapshot")
  }
  let indexed = match snapshot.walk_result("") {
    Ok(nodes) => nodes
    Err(_) => fail("index walk")
  }
  assert_true(indexed.length() >= 2)
  for node in indexed {
    assert_eq(node.format, @metadata.V2)
  }
  guard @fs.FileStore::open_consolidated_v3(
      "integration/fixtures/zarr-python/v3_consolidated_grouped_u8.zarr",
    )
    is Some(snapshot) else {
    fail("snapshot v3")
  }
  let indexed = match snapshot.walk_result("") {
    Ok(nodes) => nodes
    Err(_) => fail("index walk v3")
  }
  assert_true(indexed.length() >= 2)
  for node in indexed {
    assert_eq(node.format, @metadata.V3)
  }
}
