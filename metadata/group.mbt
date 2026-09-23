///|
/// Validated group metadata. V2 attributes live in a separate `.zattrs` key;
/// V3 attributes are part of the group's `zarr.json` document.
pub(all) struct GroupMetadata {
  format : Format
  attributes : Json
} derive(Debug)

///|
pub fn parse_group_metadata(raw : String) -> GroupMetadata? {
  let value = @json.parse(raw) catch { _ => return None }
  guard value is Object(_) else { return None }
  guard field(value, "zarr_format") is Some(version) else { return None }
  match nonnegative_int(version) {
    Some(2) => Some({ format: V2, attributes: Json::empty_object() })
    Some(3) => {
      guard string_field(value, "node_type") is Some("group") else {
        return None
      }
      let attributes = match field(value, "attributes") {
        None => Json::empty_object()
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
/// Extract v3 attributes from a validated array or group document.
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
