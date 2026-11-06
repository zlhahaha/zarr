///|
test "memory discovery validates explicit nodes and sorts breadth first" {
  let store = @store.MemoryStore::new()
  assert_true(@hierarchy.create_group_tree(store, @metadata.V3, "z/deep"))
  assert_true(@hierarchy.create_group_tree(store, @metadata.V3, "a"))
  let raw = "{\"zarr_format\":3,\"node_type\":\"array\",\"shape\":[1],\"data_type\":\"uint8\",\"chunk_grid\":{\"name\":\"regular\",\"configuration\":{\"chunk_shape\":[1]}},\"chunk_key_encoding\":{\"name\":\"default\"},\"fill_value\":0,\"codecs\":[{\"name\":\"bytes\"}],\"attributes\":{}}"
  assert_true(store.put_array_metadata(@metadata.V3, "a/image", raw))
  store.put("a/image/c/0", b"x")
  store.put("notes/file", b"ignored")
  store.put("unmarked/hidden/zarr.json", @utf8.encode(raw))
  let children = match @hierarchy.list_children(store, "") {
    Ok(nodes) => nodes
    Err(_) => fail("children")
  }
  assert_eq(children.map(node => node.path), ["a", "z"])
  let tree = match @hierarchy.walk(store, "") {
    Ok(nodes) => nodes
    Err(_) => fail("walk")
  }
  assert_eq(tree.map(node => node.path), ["a", "z", "a/image", "z/deep"])
  assert_eq(tree[2].kind, @hierarchy.ArrayNode)
  assert_true(
    @hierarchy.walk(store, "", max_nodes=3) is Err(@store.LimitExceeded(_, _)),
  )
  assert_true(
    @hierarchy.walk(store, "", max_depth=1) is Err(@store.LimitExceeded(_, _)),
  )
  assert_true(
    @hierarchy.list_children(store, "a/image")
    is Err(@store.NotGroup("a/image")),
  )
  assert_true(
    @hierarchy.list_children(store, "missing")
    is Err(@store.NotFound("missing")),
  )
  assert_true(
    @hierarchy.list_children(store, "a//image") is Err(@store.InvalidPath(_)),
  )
  assert_true(
    @hierarchy.list_children(store, "", max_keys=2)
    is Err(@store.LimitExceeded(_, _)),
  )
}

///|
test "discovery never hides malformed or conflicting metadata" {
  let store = @store.MemoryStore::new()
  assert_true(@hierarchy.create_group_tree(store, @metadata.V2, "child"))
  store.put("child/zarr.json", b"{}")
  assert_true(
    @hierarchy.list_children(store, "") is Err(@store.InvalidMetadata("child")),
  )
  store.delete("child/zarr.json")
  store.put("child/.zgroup", b"not-json")
  assert_true(
    @hierarchy.list_children(store, "") is Err(@store.InvalidMetadata("child")),
  )
  guard @store.ReadLimits::new(max_metadata_bytes=4) is Some(limits) else {
    fail("limits")
  }
  assert_true(
    @hierarchy.classify_node(
      "",
      None,
      Some(b"{\"zarr_format\":2}"),
      None,
      limits,
    )
    is Err(@store.LimitExceeded("metadata", "")),
  )
}

///|
test "discovery uses lexical names and retains legal v2 reserved-looking groups" {
  assert_eq(
    @hierarchy.child_candidates("", ["zz/zarr.json", "alpha/zarr.json"], 8),
    Ok(["alpha", "zz"]),
  )
  let store = @store.MemoryStore::new()
  assert_true(@hierarchy.create_group_tree(store, @metadata.V2, "__legal_v2"))
  let children = match @hierarchy.list_children(store, "") {
    Ok(nodes) => nodes
    Err(_) => fail("v2 listing")
  }
  assert_eq(children.map(node => node.path), ["__legal_v2"])
}
