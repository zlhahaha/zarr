///|
/// Version of the Zarr storage specification, not the Python package version.
pub(all) enum Format {
  V2
  V3
} derive(Eq, Debug)

///|
/// Validated metadata needed to locate chunks in a regular grid.
/// Codecs are retained verbatim; decoding them is a separate capability.
pub(all) struct ArrayMetadata {
  format : Format
  shape : Array[Int]
  chunk_shape : Array[Int]
  data_type : String
  separator : String
  key_encoding : String
  codecs : Array[Json]
  storage_transformers : Array[Json]
  fill_value : Json
  order : String
} derive(Debug)

///|
fn field(value : Json, name : String) -> Json? {
  match value {
    Object(map) => map.get(name)
    _ => None
  }
}

///|
fn string_field(value : Json, name : String) -> String? {
  match field(value, name) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
fn nonnegative_int(value : Json) -> Int? {
  match value {
    Number(n, ..) =>
      if n < 0.0 || n > 2147483647.0 {
        None
      } else {
        let i = n.to_int()
        if i.to_double() == n {
          Some(i)
        } else {
          None
        }
      }
    _ => None
  }
}

///|
fn dimensions(value : Json, positive : Bool) -> Array[Int]? {
  guard value is Array(values) else { return None }
  let result : Array[Int] = []
  for value in values {
    guard nonnegative_int(value) is Some(n) else { return None }
    if positive && n == 0 {
      return None
    }
    result.push(n)
  }
  Some(result)
}

///|
fn parse_v2(value : Json) -> ArrayMetadata? {
  guard field(value, "shape") is Some(shape_json) else { return None }
  guard dimensions(shape_json, false) is Some(shape) else { return None }
  guard field(value, "chunks") is Some(chunks_json) else { return None }
  guard dimensions(chunks_json, true) is Some(chunk_shape) else { return None }
  if shape.length() != chunk_shape.length() {
    return None
  }
  guard string_field(value, "dtype") is Some(data_type) else { return None }
  guard string_field(value, "order") is Some(order) else { return None }
  if order != "C" && order != "F" {
    return None
  }
  guard field(value, "compressor") is Some(compressor) else { return None }
  guard field(value, "filters") is Some(filters) else { return None }
  guard field(value, "fill_value") is Some(fill_value) else { return None }
  let separator = match field(value, "dimension_separator") {
    None => "."
    Some(String(s)) => s
    _ => return None
  }
  if separator != "." && separator != "/" {
    return None
  }
  let codecs : Array[Json] = []
  match filters {
    Null => ()
    Array(items) =>
      for item in items {
        codecs.push(item)
      }
    _ => return None
  }
  match compressor {
    Null => ()
    Object(_) => codecs.push(compressor)
    _ => return None
  }
  Some({
    format: V2,
    shape,
    chunk_shape,
    data_type,
    separator,
    key_encoding: "v2",
    codecs,
    storage_transformers: [],
    fill_value,
    order,
  })
}

///|
fn parse_v3(value : Json) -> ArrayMetadata? {
  guard string_field(value, "node_type") is Some("array") else { return None }
  guard field(value, "shape") is Some(shape_json) else { return None }
  guard dimensions(shape_json, false) is Some(shape) else { return None }
  guard string_field(value, "data_type") is Some(data_type) else { return None }
  guard field(value, "chunk_grid") is Some(grid) else { return None }
  guard string_field(grid, "name") is Some("regular") else { return None }
  guard field(grid, "configuration") is Some(grid_config) else { return None }
  guard field(grid_config, "chunk_shape") is Some(chunks_json) else {
    return None
  }
  guard dimensions(chunks_json, true) is Some(chunk_shape) else { return None }
  if shape.length() != chunk_shape.length() {
    return None
  }
  guard field(value, "chunk_key_encoding") is Some(encoding) else {
    return None
  }
  guard string_field(encoding, "name") is Some(key_encoding) else {
    return None
  }
  if key_encoding != "default" && key_encoding != "v2" {
    return None
  }
  let default_separator = if key_encoding == "default" { "/" } else { "." }
  let separator = match field(encoding, "configuration") {
    None => default_separator
    Some(config) =>
      match field(config, "separator") {
        None => default_separator
        Some(String(s)) => s
        _ => return None
      }
  }
  if separator != "." && separator != "/" {
    return None
  }
  guard field(value, "codecs") is Some(Array(codecs)) else { return None }
  if codecs.length() == 0 {
    return None
  }
  let storage_transformers = match field(value, "storage_transformers") {
    None => []
    Some(Array(items)) => items
    _ => return None
  }
  guard field(value, "fill_value") is Some(fill_value) else { return None }
  Some({
    format: V3,
    shape,
    chunk_shape,
    data_type,
    separator,
    key_encoding,
    codecs,
    storage_transformers,
    fill_value,
    order: "C",
  })
}

///|
/// Parse array metadata from either `.zarray` (v2) or `zarr.json` (v3).
/// Returns None for invalid or unsupported metadata; no chunk decoding occurs.
pub fn parse_array_metadata(raw : String) -> ArrayMetadata? {
  let value = @json.parse(raw) catch { _ => return None }
  guard field(value, "zarr_format") is Some(version) else { return None }
  match nonnegative_int(version) {
    Some(2) => parse_v2(value)
    Some(3) => parse_v3(value)
    _ => None
  }
}
