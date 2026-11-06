///|
pub async fn FileStore::open_node_result(
  self : FileStore,
  path : String,
) -> Result[@hierarchy.Node, @store.AccessError] {
  if !@hierarchy.discovery_path(path) || (path != "" && self.path(path) is None) {
    return Err(@store.InvalidPath(path))
  }
  let prefix = if path == "" { "" } else { "\{path}/" }
  let markers = (
    self.get("\{prefix}.zarray"),
    self.get("\{prefix}.zgroup"),
    self.get("\{prefix}zarr.json"),
  ) catch {
    ReadLimitExceeded(_) => return Err(@store.LimitExceeded("metadata", path))
    @os_error.OSError(_) => return Err(@store.Io(path))
    error => raise error
  }
  let (array, group, v3) = markers
  match @hierarchy.classify_node(path, array, group, v3, self.limits) {
    Ok(Some(node)) => Ok(node)
    Ok(None) => Err(@store.NotFound(path))
    Err(error) => Err(error)
  }
}

///|
pub async fn FileStore::list_children_result(
  self : FileStore,
  path : String,
  max_nodes~ : Int32 = 4096,
  max_entries~ : Int32 = 65536,
) -> Result[Array[@hierarchy.Node], @store.AccessError] {
  if max_nodes <= 0 || max_entries <= 0 {
    return Err(@store.LimitExceeded("listing policy", path))
  }
  let parent = match self.open_node_result(path) {
    Err(error) => return Err(error)
    Ok({ kind: @hierarchy.ArrayNode, .. }) => return Err(@store.NotGroup(path))
    Ok(node) => node
  }
  let candidates : Array[String] = []
  let keys : Array[String] = []
  if self.consolidated is Some(entries) {
    for key, _ in entries {
      if keys.length() >= max_entries {
        return Err(@store.LimitExceeded("metadata keys", path))
      }
      keys.push(key)
    }
  } else if self.v3_consolidated is Some(entries) {
    for key, _ in entries {
      if keys.length() >= max_entries {
        return Err(@store.LimitExceeded("metadata keys", path))
      }
      keys.push("\{key}/zarr.json")
    }
  } else {
    let directory_path = if path == "" {
      self.root
    } else {
      guard self.path(path) is Some(value) else {
        return Err(@store.InvalidPath(path))
      }
      value
    }
    try {
      let directory = @async_fs.opendir(directory_path)
      defer directory.close()
      let mut examined = 0
      while directory.next() is Some(entry) {
        examined += 1
        if examined > max_entries {
          return Err(@store.LimitExceeded("directory entries", path))
        }
        if entry.is_dir &&
          !(parent.format == @metadata.V3 && entry.name.has_prefix("__")) {
          let child = if path == "" {
            entry.name
          } else {
            "\{path}/\{entry.name}"
          }
          if @hierarchy.discovery_path(child) && self.path(child) is Some(_) {
            candidates.push(child)
          }
        }
      }
    } catch {
      @os_error.OSError(_) => return Err(@store.Io(path))
      error => raise error
    }
  }
  if self.read_only {
    match @hierarchy.child_candidates(path, keys, max_entries) {
      Ok(paths) => candidates.append(paths[:])
      Err(error) => return Err(error)
    }
  }
  candidates.sort_by((a, b) => a[:].lexical_compare(b))
  let nodes : Array[@hierarchy.Node] = []
  for candidate in candidates {
    if parent.format == @metadata.V3 {
      let name = if path == "" {
        candidate[:]
      } else {
        candidate[path.length() + 1:]
      }
      if name.has_prefix("__") {
        continue
      }
    }
    match self.open_node_result(candidate) {
      Ok(node) => {
        if nodes.length() >= max_nodes {
          return Err(@store.LimitExceeded("children", path))
        }
        nodes.push(node)
      }
      Err(@store.NotFound(_)) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(nodes)
}

///|
pub async fn FileStore::walk_result(
  self : FileStore,
  path : String,
  max_nodes~ : Int32 = 4096,
  max_depth~ : Int32 = 64,
  max_entries~ : Int32 = 65536,
) -> Result[Array[@hierarchy.Node], @store.AccessError] {
  if max_nodes <= 0 || max_depth < 0 {
    return Err(@store.LimitExceeded("walk policy", path))
  }
  let queue = [(path, 0)]
  let nodes : Array[@hierarchy.Node] = []
  let mut position = 0
  while position < queue.length() {
    let (group, depth) = queue[position]
    position += 1
    let children = match
      self.list_children_result(group, max_nodes~, max_entries~) {
      Ok(children) => children
      Err(error) => return Err(error)
    }
    if children.length() > max_nodes - nodes.length() ||
      (depth >= max_depth && !children.is_empty()) {
      return Err(@store.LimitExceeded("walk", group))
    }
    for node in children {
      nodes.push(node)
      if node.kind == @hierarchy.GroupNode {
        queue.push((node.path, depth + 1))
      }
    }
  }
  Ok(nodes)
}
