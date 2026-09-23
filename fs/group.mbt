///|
pub async fn FileStore::put_group_metadata(
  self : FileStore,
  format : @zarr.Format,
  path : String,
  raw : String,
) -> Bool {
  guard @zarr.parse_group_metadata(raw) is Some(metadata) else { return false }
  if metadata.format != format {
    return false
  }
  guard @zarr.group_metadata_key(format, path) is Some(key) else {
    return false
  }
  guard @zarr.array_metadata_key(format, path) is Some(array_key) else {
    return false
  }
  if format == @zarr.V2 && self.get(array_key) is Some(_) {
    return false
  }
  if format == @zarr.V3 && self.get(key) is Some(bytes) {
    let previous = @utf8.decode(bytes[:]) catch { _ => return false }
    if @zarr.parse_array_metadata(previous) is Some(_) {
      return false
    }
  }
  self.put(key, @utf8.encode(raw))
}

///|
pub async fn FileStore::open_group(
  self : FileStore,
  path : String,
) -> @zarr.GroupMetadata? {
  guard @zarr.group_metadata_key(@zarr.V2, path) is Some(v2_key) else {
    return None
  }
  guard @zarr.group_metadata_key(@zarr.V3, path) is Some(v3_key) else {
    return None
  }
  guard @zarr.array_metadata_key(@zarr.V2, path) is Some(v2_array_key) else {
    return None
  }
  if self.get(v2_array_key) is Some(_) {
    return None
  }
  let v2 = self.get(v2_key)
  let v3 = self.get(v3_key)
  let (format, bytes) = match (v2, v3) {
    (Some(bytes), None) => (@zarr.V2, bytes)
    (None, Some(bytes)) => (@zarr.V3, bytes)
    _ => return None
  }
  let raw = @utf8.decode(bytes[:]) catch { _ => return None }
  guard @zarr.parse_group_metadata(raw) is Some(metadata) else { return None }
  if metadata.format != format {
    return None
  }
  if format == @zarr.V3 {
    return Some(metadata)
  }
  guard @zarr.attributes_key(@zarr.V2, path) is Some(attrs_key) else {
    return None
  }
  let attributes = match self.get(attrs_key) {
    None => metadata.attributes
    Some(attrs_bytes) => {
      let attrs_raw = @utf8.decode(attrs_bytes[:]) catch { _ => return None }
      guard @zarr.parse_attributes(attrs_raw) is Some(attrs) else {
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
  format : @zarr.Format,
  path : String,
) -> @zarr.MemoryStore? {
  guard @zarr.group_metadata_key(format, path) is Some(group_key) else {
    return None
  }
  let scratch = @zarr.MemoryStore::new()
  if self.get(group_key) is Some(bytes) {
    scratch.put(group_key, bytes)
  }
  if format == @zarr.V2 {
    guard @zarr.array_metadata_key(format, path) is Some(array_key) else {
      return None
    }
    guard @zarr.attributes_key(format, path) is Some(attrs_key) else {
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
  format : @zarr.Format,
  path : String,
) -> Json? {
  guard self.attributes_scratch(format, path) is Some(scratch) else {
    return None
  }
  scratch.read_attributes(format, path)
}

///|
pub async fn FileStore::put_attributes(
  self : FileStore,
  format : @zarr.Format,
  path : String,
  attributes_raw : String,
) -> Bool {
  guard self.attributes_scratch(format, path) is Some(scratch) else {
    return false
  }
  if !scratch.put_attributes(format, path, attributes_raw) {
    return false
  }
  let key = if format == @zarr.V2 {
    @zarr.attributes_key(format, path)
  } else {
    @zarr.group_metadata_key(format, path)
  }
  guard key is Some(key) else { return false }
  guard scratch.get(key) is Some(bytes) else { return false }
  self.put(key, bytes)
}
