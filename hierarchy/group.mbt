///|
/// Store a validated v2 or v3 group document without replacing an array.
pub fn put_group_metadata(
  store : @store.MemoryStore,
  format : @metadata.Format,
  path : String,
  raw : String,
) -> Bool {
  guard @metadata.parse_group_metadata(raw) is Some(group) else { return false }
  if group.format != format {
    return false
  }
  guard @chunk.group_metadata_key(format, path) is Some(key) else {
    return false
  }
  guard @chunk.array_metadata_key(format, path) is Some(array_key) else {
    return false
  }
  if format == @metadata.V2 && store.get(array_key) is Some(_) {
    return false
  }
  if format == @metadata.V3 && store.get(key) is Some(bytes) {
    let previous = @utf8.decode(bytes[:]) catch { _ => return false }
    if @metadata.parse_array_metadata(previous) is Some(_) {
      return false
    }
  }
  store.put(key, @utf8.encode(raw))
  true
}

///|
/// Open a group only when the path unambiguously identifies a format and
/// node type. Missing v2 `.zattrs` is an empty object.
pub fn open_group(
  store : @store.MemoryStore,
  path : String,
) -> @metadata.GroupMetadata? {
  guard @chunk.group_metadata_key(@metadata.V2, path) is Some(v2_key) else {
    return None
  }
  guard @chunk.group_metadata_key(@metadata.V3, path) is Some(v3_key) else {
    return None
  }
  guard @chunk.array_metadata_key(@metadata.V2, path) is Some(v2_array_key) else {
    return None
  }
  if store.get(v2_array_key) is Some(_) {
    return None
  }
  let (format, bytes) = match (store.get(v2_key), store.get(v3_key)) {
    (Some(bytes), None) => (@metadata.V2, bytes)
    (None, Some(bytes)) => (@metadata.V3, bytes)
    _ => return None
  }
  let raw = @utf8.decode(bytes[:]) catch { _ => return None }
  guard @metadata.parse_group_metadata(raw) is Some(group) else { return None }
  if group.format != format {
    return None
  }
  if format == @metadata.V3 {
    return Some(group)
  }
  guard @chunk.attributes_key(format, path) is Some(attrs_key) else {
    return None
  }
  let attributes = match store.get(attrs_key) {
    None => group.attributes
    Some(attrs_bytes) => {
      let attrs_raw = @utf8.decode(attrs_bytes[:]) catch { _ => return None }
      guard @metadata.parse_attributes(attrs_raw) is Some(attrs) else {
        return None
      }
      attrs
    }
  }
  Some({ format, attributes })
}

///|
fn v2_node_exists(store : @store.MemoryStore, path : String) -> Bool {
  guard @chunk.group_metadata_key(@metadata.V2, path) is Some(group_key) else {
    return false
  }
  guard @chunk.array_metadata_key(@metadata.V2, path) is Some(array_key) else {
    return false
  }
  let group = store.get(group_key)
  let array = store.get(array_key)
  if group is Some(_) && array is Some(_) {
    return false
  }
  if group is Some(bytes) {
    let raw = @utf8.decode(bytes[:]) catch { _ => return false }
    guard @metadata.parse_group_metadata(raw) is Some(meta) else {
      return false
    }
    return meta.format == @metadata.V2
  }
  if array is Some(bytes) {
    let raw = @utf8.decode(bytes[:]) catch { _ => return false }
    guard @metadata.parse_array_metadata(raw) is Some(meta) else {
      return false
    }
    return meta.format == @metadata.V2
  }
  false
}

///|
pub fn read_attributes(
  store : @store.MemoryStore,
  format : @metadata.Format,
  path : String,
) -> Json? {
  guard @chunk.group_metadata_key(format, path) is Some(metadata_key) else {
    return None
  }
  if format == @metadata.V2 {
    if !v2_node_exists(store, path) {
      return None
    }
    guard @chunk.attributes_key(format, path) is Some(key) else { return None }
    match store.get(key) {
      None => Some(Json::empty_object())
      Some(bytes) => {
        let raw = @utf8.decode(bytes[:]) catch { _ => return None }
        @metadata.parse_attributes(raw)
      }
    }
  } else {
    guard store.get(metadata_key) is Some(bytes) else { return None }
    let raw = @utf8.decode(bytes[:]) catch { _ => return None }
    @metadata.v3_attributes(raw)
  }
}

///|
/// Replace attributes of an existing group or array.
pub fn put_attributes(
  store : @store.MemoryStore,
  format : @metadata.Format,
  path : String,
  attributes_raw : String,
) -> Bool {
  guard @metadata.parse_attributes(attributes_raw) is Some(_) else {
    return false
  }
  guard @chunk.group_metadata_key(format, path) is Some(metadata_key) else {
    return false
  }
  if format == @metadata.V2 {
    if !v2_node_exists(store, path) {
      return false
    }
    guard @chunk.attributes_key(format, path) is Some(key) else { return false }
    store.put(key, @utf8.encode(attributes_raw))
    true
  } else {
    guard store.get(metadata_key) is Some(bytes) else { return false }
    let raw = @utf8.decode(bytes[:]) catch { _ => return false }
    guard @metadata.replace_v3_attributes(raw, attributes_raw) is Some(updated) else {
      return false
    }
    store.put(metadata_key, @utf8.encode(updated))
    true
  }
}
