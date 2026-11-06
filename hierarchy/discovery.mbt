///|
#derive(Eq, Debug)
pub(all) enum NodeKind {
  ArrayNode
  GroupNode
}

///|
pub extend NodeKind with Eq::{equal, not_equal}

///|
pub extend NodeKind with Debug::{to_repr}

///|
/// A metadata-validated explicit hierarchy node. Chunk directories and
/// unmarked prefixes are not nodes. Paths are store-relative, root is "".
#derive(Eq, Debug)
pub(all) struct Node {
  path : String
  kind : NodeKind
  format : @metadata.Format
}

///|
pub extend Node with Eq::{equal, not_equal}

///|
pub extend Node with Debug::{to_repr}

///|
/// Shared strict path check for discovery; do not silently normalize aliases.
pub fn discovery_path(path : String) -> Bool {
  @chunk.normalized_path(path, @metadata.V2) == Some(path) &&
  !path.contains("\\")
}

///|
/// Classify a node from all possible metadata markers. Conflicting versions,
/// malformed documents and over-budget metadata are errors, not absence.
pub fn classify_node(
  path : String,
  v2_array : Bytes?,
  v2_group : Bytes?,
  v3 : Bytes?,
  limits : @store.ReadLimits,
) -> Result[Node?, @store.AccessError] {
  if !discovery_path(path) {
    return Err(@store.InvalidPath(path))
  }
  let present : Array[(@metadata.Format, Bool, Bytes)] = []
  if v2_array is Some(bytes) {
    present.push((@metadata.V2, true, bytes))
  }
  if v2_group is Some(bytes) {
    present.push((@metadata.V2, false, bytes))
  }
  if v3 is Some(bytes) {
    present.push((@metadata.V3, false, bytes))
  }
  if present.length() == 0 {
    return Ok(None)
  }
  if present.length() != 1 {
    return Err(@store.InvalidMetadata(path))
  }
  let (format, array_marker, bytes) = present[0]
  if @chunk.normalized_path(path, format) != Some(path) {
    return Err(@store.InvalidPath(path))
  }
  if !limits.allows_metadata(bytes) {
    return Err(@store.LimitExceeded("metadata", path))
  }
  let raw = @utf8.decode(bytes[:]) catch {
    _ => return Err(@store.InvalidMetadata(path))
  }
  if @metadata.parse_array_metadata(raw) is Some(array) {
    if array.format != format || (format == @metadata.V2 && !array_marker) {
      return Err(@store.InvalidMetadata(path))
    }
    Ok(Some({ path, kind: ArrayNode, format, }))
  } else if @metadata.parse_group_metadata(raw) is Some(group) {
    if group.format != format || (format == @metadata.V2 && array_marker) {
      return Err(@store.InvalidMetadata(path))
    }
    Ok(Some({ path, kind: GroupNode, format, }))
  } else {
    Err(@store.InvalidMetadata(path))
  }
}

///|
/// Extract sorted immediate candidate paths from metadata keys. This is not
/// classification: adapters still validate each candidate's metadata.
pub fn child_candidates(
  path : String,
  keys : Array[String],
  max_children : Int32,
) -> Result[Array[String], @store.AccessError] {
  if !discovery_path(path) {
    return Err(@store.InvalidPath(path))
  }
  if max_children <= 0 {
    return Err(@store.LimitExceeded("children", path))
  }
  let prefix = if path == "" { "" } else { "\{path}/" }
  let found : Map[String, Bool] = Map([])
  for key in keys {
    if key.has_prefix(prefix) {
      let tail = key[prefix.length():]
      if tail.split_once("/") is Some((name, _)) {
        let candidate = "\{prefix}\{name}"
        if name != "" && discovery_path(candidate) {
          found[candidate] = true
          if found.length() > max_children {
            return Err(@store.LimitExceeded("children", path))
          }
        }
      }
    }
  }
  let result = found.keys().collect()
  result.sort_by((a, b) => a[:].lexical_compare(b))
  Ok(result)
}

///|
pub fn open_node(
  store : @store.MemoryStore,
  path : String,
) -> Result[Node?, @store.AccessError] {
  if !discovery_path(path) {
    return Err(@store.InvalidPath(path))
  }
  let prefix = if path == "" { "" } else { "\{path}/" }
  classify_node(
    path,
    store.get("\{prefix}.zarray"),
    store.get("\{prefix}.zgroup"),
    store.get("\{prefix}zarr.json"),
    store.read_limits(),
  )
}

///|
/// Sorted explicit child nodes. Unmarked directories/prefixes are ignored.
pub fn list_children(
  store : @store.MemoryStore,
  path : String,
  max_nodes~ : Int32 = 4096,
  max_keys~ : Int32 = 65536,
) -> Result[Array[Node], @store.AccessError] {
  if max_nodes <= 0 || max_keys <= 0 {
    return Err(@store.LimitExceeded("listing policy", path))
  }
  let parent = match open_node(store, path) {
    Err(error) => return Err(error)
    Ok(None) => return Err(@store.NotFound(path))
    Ok(Some({ kind: ArrayNode, .. })) => return Err(@store.NotGroup(path))
    Ok(Some(node)) => node
  }
  let prefix = if path == "" { "" } else { "\{path}/" }
  let keys = match store.list_metadata_keys(prefix~, max_keys~) {
    Ok(keys) => keys
    Err(error) => return Err(error)
  }
  let candidates = match child_candidates(path, keys, max_keys) {
    Ok(paths) => paths
    Err(error) => return Err(error)
  }
  let nodes : Array[Node] = []
  for candidate in candidates {
    let name = candidate[prefix.length():]
    if parent.format == @metadata.V3 && name.has_prefix("__") {
      continue
    }
    match open_node(store, candidate) {
      Ok(Some(node)) => {
        if nodes.length() >= max_nodes {
          return Err(@store.LimitExceeded("children", path))
        }
        nodes.push(node)
      }
      Ok(None) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(nodes)
}

///|
/// Deterministic breadth-first descendants; excludes the starting group.
/// Limits reject the operation rather than silently returning a partial tree.
pub fn walk(
  store : @store.MemoryStore,
  path : String,
  max_nodes~ : Int32 = 4096,
  max_depth~ : Int32 = 64,
  max_keys~ : Int32 = 65536,
) -> Result[Array[Node], @store.AccessError] {
  if max_nodes <= 0 || max_depth < 0 {
    return Err(@store.LimitExceeded("walk policy", path))
  }
  let queue = [(path, 0)]
  let nodes : Array[Node] = []
  let mut position = 0
  while position < queue.length() {
    let (group, depth) = queue[position]
    position += 1
    let children = match list_children(store, group, max_nodes~, max_keys~) {
      Ok(children) => children
      Err(error) => return Err(error)
    }
    if children.length() > max_nodes - nodes.length() ||
      (depth >= max_depth && !children.is_empty()) {
      return Err(@store.LimitExceeded("walk", group))
    }
    for node in children {
      nodes.push(node)
      if node.kind == GroupNode {
        queue.push((node.path, depth + 1))
      }
    }
  }
  Ok(nodes)
}
