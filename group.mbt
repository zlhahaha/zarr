///|
/// Validated group metadata. V2 attributes live in a separate `.zattrs` key;
/// V3 attributes are part of the group's `zarr.json` document.
pub(all) struct GroupMetadata {
  format : Format
  attributes : Json
} derive(Debug)

///|
pub fn group_metadata_key(format : Format, path : String) -> String? {
  guard normalized_path(path, format) is Some(prefix) else { return None }
  let name = if format == V2 { ".zgroup" } else { "zarr.json" }
  Some(if prefix == "" { name } else { "\{prefix}/\{name}" })
}

///|
pub fn attributes_key(format : Format, path : String) -> String? {
  if format != V2 {
    return None
  }
  guard normalized_path(path, format) is Some(prefix) else { return None }
  Some(if prefix == "" { ".zattrs" } else { "\{prefix}/.zattrs" })
}

///|
pub fn parse_group_metadata(raw : String) -> GroupMetadata? {
  let value = @json.parse(raw) catch { _ => return None }
  guard value is Object(_) else { return None }
  guard field(value, "zarr_format") is Some(version) else { return None }
  match nonnegative_int(version) {
    Some(2) => Some({ format: V2, attributes: Json::object(Map([])) })
    Some(3) => {
      guard string_field(value, "node_type") is Some("group") else {
        return None
      }
      let attributes = match field(value, "attributes") {
        None => Json::object(Map([]))
        Some(Object(map)) => Json::object(map)
        _ => return None
      }
      Some({ format: V3, attributes })
    }
    _ => None
  }
}

///|
pub fn parse_attributes(raw : String) -> Json? {
  let value = @json.parse(raw) catch { _ => return None }
  guard value is Object(_) else { return None }
  Some(value)
}

///|
pub fn MemoryStore::put_group_metadata(
  self : MemoryStore,
  format : Format,
  path : String,
  raw : String,
) -> Bool {
  guard parse_group_metadata(raw) is Some(metadata) else { return false }
  if metadata.format != format {
    return false
  }
  guard group_metadata_key(format, path) is Some(key) else { return false }
  guard array_metadata_key(format, path) is Some(array_key) else {
    return false
  }
  if format == V2 && self.get(array_key) is Some(_) {
    return false
  }
  if format == V3 && self.get(key) is Some(bytes) {
    let previous = @utf8.decode(bytes[:]) catch { _ => return false }
    if parse_array_metadata(previous) is Some(_) {
      return false
    }
  }
  self.put(key, @utf8.encode(raw))
  true
}

///|
/// Open a group only when the path unambiguously identifies one format and
/// one node type. V2 `.zattrs` is optional and defaults to an empty object.
pub fn MemoryStore::open_group(
  self : MemoryStore,
  path : String,
) -> GroupMetadata? {
  guard group_metadata_key(V2, path) is Some(v2_key) else { return None }
  guard group_metadata_key(V3, path) is Some(v3_key) else { return None }
  guard array_metadata_key(V2, path) is Some(v2_array_key) else { return None }
  let v2 = self.get(v2_key)
  let v3 = self.get(v3_key)
  if self.get(v2_array_key) is Some(_) {
    return None
  }
  let (format, bytes) = match (v2, v3) {
    (Some(bytes), None) => (V2, bytes)
    (None, Some(bytes)) => (V3, bytes)
    _ => return None
  }
  let raw = @utf8.decode(bytes[:]) catch { _ => return None }
  guard parse_group_metadata(raw) is Some(metadata) else { return None }
  if metadata.format != format {
    return None
  }
  if format == V3 {
    return Some(metadata)
  }
  guard attributes_key(V2, path) is Some(attrs_key) else { return None }
  let attributes = match self.get(attrs_key) {
    None => metadata.attributes
    Some(attrs_bytes) => {
      let attrs_raw = @utf8.decode(attrs_bytes[:]) catch { _ => return None }
      guard parse_attributes(attrs_raw) is Some(attrs) else { return None }
      attrs
    }
  }
  Some({ format, attributes })
}

///|
/// Extract v3 attributes from a validated array or group document.
/// Missing attributes are equivalent to an empty object.
pub fn v3_attributes(raw : String) -> Json? {
  if parse_array_metadata(raw) is None && parse_group_metadata(raw) is None {
    return None
  }
  let value = @json.parse(raw) catch { _ => return None }
  match field(value, "attributes") {
    None => Some(Json::empty_object())
    Some(Object(map)) => Some(Json::object(map))
    _ => None
  }
}

///|
/// Return a valid v3 metadata document with its attributes replaced.
pub fn replace_v3_attributes(raw : String, attributes_raw : String) -> String? {
  guard parse_attributes(attributes_raw) is Some(attributes) else {
    return None
  }
  guard v3_attributes(raw) is Some(_) else { return None }
  let value = @json.parse(raw) catch { _ => return None }
  guard value is Object(fields) else { return None }
  fields.set("attributes", attributes)
  Some(Json::object(fields).stringify())
}

///|
fn MemoryStore::v2_node_exists(self : MemoryStore, path : String) -> Bool {
  guard group_metadata_key(V2, path) is Some(group_key) else { return false }
  guard array_metadata_key(V2, path) is Some(array_key) else { return false }
  let group = self.get(group_key)
  let array = self.get(array_key)
  if group is Some(_) && array is Some(_) {
    return false
  }
  if group is Some(bytes) {
    let raw = @utf8.decode(bytes[:]) catch { _ => return false }
    guard parse_group_metadata(raw) is Some(metadata) else { return false }
    return metadata.format == V2
  }
  if array is Some(bytes) {
    let raw = @utf8.decode(bytes[:]) catch { _ => return false }
    guard parse_array_metadata(raw) is Some(metadata) else { return false }
    return metadata.format == V2
  }
  false
}

///|
/// Read attributes for a known format and path. This avoids guessing the
/// format when both v2 and v3 happen to use the same logical path.
pub fn MemoryStore::read_attributes(
  self : MemoryStore,
  format : Format,
  path : String,
) -> Json? {
  guard group_metadata_key(format, path) is Some(metadata_key) else {
    return None
  }
  if format == V2 {
    if !self.v2_node_exists(path) {
      return None
    }
    guard attributes_key(V2, path) is Some(key) else { return None }
    match self.get(key) {
      None => Some(Json::empty_object())
      Some(bytes) => {
        let raw = @utf8.decode(bytes[:]) catch { _ => return None }
        parse_attributes(raw)
      }
    }
  } else {
    guard self.get(metadata_key) is Some(bytes) else { return None }
    let raw = @utf8.decode(bytes[:]) catch { _ => return None }
    v3_attributes(raw)
  }
}

///|
/// Replace attributes on an existing array or group. V2 writes `.zattrs`;
/// V3 updates `zarr.json` while preserving its other fields.
pub fn MemoryStore::put_attributes(
  self : MemoryStore,
  format : Format,
  path : String,
  attributes_raw : String,
) -> Bool {
  guard parse_attributes(attributes_raw) is Some(_) else { return false }
  guard group_metadata_key(format, path) is Some(metadata_key) else {
    return false
  }
  if format == V2 {
    if !self.v2_node_exists(path) {
      return false
    }
    guard attributes_key(V2, path) is Some(key) else { return false }
    self.put(key, @utf8.encode(attributes_raw))
    true
  } else {
    guard self.get(metadata_key) is Some(bytes) else { return false }
    let raw = @utf8.decode(bytes[:]) catch { _ => return false }
    guard replace_v3_attributes(raw, attributes_raw) is Some(updated) else {
      return false
    }
    self.put(metadata_key, @utf8.encode(updated))
    true
  }
}
