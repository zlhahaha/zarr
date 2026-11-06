///|
fn main {
  let store = @store.MemoryStore::new()
  if !@hierarchy.create_group_tree(store, @metadata.V3, "experiment/session") {
    abort("group creation")
  }
  guard @array.create_u8(
      store,
      @metadata.V3,
      "experiment/image",
      [4, 4],
      [2, 2],
      b'\x07',
    )
    is Some(_) else {
    abort("array creation")
  }
  let nodes = match @hierarchy.walk(store, "") {
    Ok(nodes) => nodes
    Err(_) => abort("hierarchy discovery")
  }
  if nodes.map(node => node.path) !=
    ["experiment", "experiment/image", "experiment/session"] {
    abort("tree contents")
  }
  if !(@hierarchy.walk(store, "", max_depth=1)
    is Err(@store.LimitExceeded("walk", "experiment"))) {
    abort("depth limit")
  }
  println(
    "Zarr discovery: 2 groups, 1 array; lexical breadth-first order and depth limit verified",
  )
}
