///|
pub async fn FileStore::put_group_metadata(
  self : FileStore,
  format : @metadata.Format,
  path : String,
  raw : String,
) -> Bool {
  guard @metadata.parse_group_metadata(raw) is Some(metadata) else {
    return false
  }
  if metadata.format != format {
    return false
  }
  guard @chunk.group_metadata_key(format, path) is Some(key) else {
    return false
  }
  guard @chunk.array_metadata_key(format, path) is Some(array_key) else {
    return false
  }
  let other = if format == @metadata.V2 { @metadata.V3 } else { @metadata.V2 }
  let other_array = match @chunk.array_metadata_key(other, path) {
    Some(key) => self.get(key) is Some(_)
    None => false
  }
  let other_group = match @chunk.group_metadata_key(other, path) {
    Some(key) => self.get(key) is Some(_)
    None => false
  }
  if other_array || other_group {
    return false
  }
  if format == @metadata.V2 && self.get(array_key) is Some(_) {
    return false
  }
  if format == @metadata.V3 && self.get(key) is Some(bytes) {
    let previous = @utf8.decode(bytes[:]) catch { _ => return false }
    if @metadata.parse_array_metadata(previous) is Some(_) {
      return false
    }
  }
  self.put(key, @utf8.encode(raw))
}

///|
/// Create the root and missing ancestor groups through `path`.
/// Existing groups of the same format are preserved.
pub async fn FileStore::create_group_tree(
  self : FileStore,
  format : @metadata.Format,
  path : String,
) -> Bool {
  guard @chunk.group_prefixes(format, path) is Some(prefixes) else {
    return false
  }
  let other = if format == @metadata.V2 { @metadata.V3 } else { @metadata.V2 }
  for prefix in prefixes {
    guard @chunk.group_metadata_key(format, prefix) is Some(own_key) else {
      return false
    }
    guard @chunk.array_metadata_key(format, prefix) is Some(own_array_key) else {
      return false
    }
    let other_group = match @chunk.group_metadata_key(other, prefix) {
      Some(key) => self.get(key) is Some(_)
      None => false
    }
    let other_array = match @chunk.array_metadata_key(other, prefix) {
      Some(key) => self.get(key) is Some(_)
      None => false
    }
    if other_group ||
      other_array ||
      (format == @metadata.V2 && self.get(own_array_key) is Some(_)) {
      return false
    }
    if self.get(own_key) is Some(_) {
      guard self.open_group(prefix) is Some(group) else { return false }
      if group.format != format {
        return false
      }
    }
  }
  let raw = @metadata.empty_group_metadata_json(format)
  for prefix in prefixes {
    guard @chunk.group_metadata_key(format, prefix) is Some(key) else {
      return false
    }
    if self.get(key) is None && !self.put_group_metadata(format, prefix, raw) {
      return false
    }
  }
  true
}

///|
pub async fn FileStore::open_group(
  self : FileStore,
  path : String,
) -> @metadata.GroupMetadata? {
  guard @chunk.group_metadata_key(@metadata.V2, path) is Some(v2_key) else {
    return None
  }
  let v3_key = @chunk.group_metadata_key(@metadata.V3, path)
  guard @chunk.array_metadata_key(@metadata.V2, path) is Some(v2_array_key) else {
    return None
  }
  if self.get(v2_array_key) is Some(_) {
    return None
  }
  let v2 = self.get(v2_key)
  let v3 = match v3_key {
    Some(key) => self.get(key)
    None => None
  }
  let (format, bytes) = match (v2, v3) {
    (Some(bytes), None) => (@metadata.V2, bytes)
    (None, Some(bytes)) => (@metadata.V3, bytes)
    _ => return None
  }
  let raw = @utf8.decode(bytes[:]) catch { _ => return None }
  guard @metadata.parse_group_metadata(raw) is Some(metadata) else {
    return None
  }
  if metadata.format != format {
    return None
  }
  if format == @metadata.V3 {
    return Some(metadata)
  }
  guard @chunk.attributes_key(@metadata.V2, path) is Some(attrs_key) else {
    return None
  }
  let attributes = match self.get(attrs_key) {
    None => metadata.attributes
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
async fn FileStore::attributes_scratch(
  self : FileStore,
  format : @metadata.Format,
  path : String,
) -> @store.MemoryStore? {
  guard @chunk.group_metadata_key(format, path) is Some(group_key) else {
    return None
  }
  let other = if format == @metadata.V2 { @metadata.V3 } else { @metadata.V2 }
  let other_array = match @chunk.array_metadata_key(other, path) {
    Some(key) => self.get(key) is Some(_)
    None => false
  }
  let other_group = match @chunk.group_metadata_key(other, path) {
    Some(key) => self.get(key) is Some(_)
    None => false
  }
  if other_array || other_group {
    return None
  }
  let scratch = @store.MemoryStore::new()
  if self.get(group_key) is Some(bytes) {
    scratch.put(group_key, bytes)
  }
  if format == @metadata.V2 {
    guard @chunk.array_metadata_key(format, path) is Some(array_key) else {
      return None
    }
    guard @chunk.attributes_key(format, path) is Some(attrs_key) else {
      return None
    }
    if self.get(array_key) is Some(bytes) {
      scratch.put(array_key, bytes)
    }
    if self.get(attrs_key) is Some(bytes) {
      scratch.put(attrs_key, bytes)
    }
  }
  Some(scratch)
}

///|
pub async fn FileStore::read_attributes(
  self : FileStore,
  format : @metadata.Format,
  path : String,
) -> Json? {
  guard self.attributes_scratch(format, path) is Some(scratch) else {
    return None
  }
  @hierarchy.read_attributes(scratch, format, path)
}

///|
pub async fn FileStore::put_attributes(
  self : FileStore,
  format : @metadata.Format,
  path : String,
  attributes_raw : String,
) -> Bool {
  guard self.attributes_scratch(format, path) is Some(scratch) else {
    return false
  }
  if !@hierarchy.put_attributes(scratch, format, path, attributes_raw) {
    return false
  }
  let key = if format == @metadata.V2 {
    @chunk.attributes_key(format, path)
  } else {
    @chunk.group_metadata_key(format, path)
  }
  guard key is Some(key) else { return false }
  guard scratch.get(key) is Some(bytes) else { return false }
  self.put(key, bytes)
}
