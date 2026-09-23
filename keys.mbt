///|
fn normalized_path(path : String, format : Format) -> String? {
  let mut result = ""
  for part in path.replace_all(old="\\", new="/").split("/") {
    let segment = "\{part}"
    if segment != "" {
      if segment == "." || segment == ".." {
        return None
      }
      if format == V3 && (segment.has_prefix("__") || segment == "zarr.json") {
        return None
      }
      if result == "" {
        result = segment
      } else {
        result = "\{result}/\{segment}"
      }
    }
  }
  Some(result)
}

///|
/// Key for the metadata of an array at a logical path.
pub fn array_metadata_key(format : Format, path : String) -> String? {
  guard normalized_path(path, format) is Some(prefix) else { return None }
  let name = match format {
    V2 => ".zarray"
    V3 => "zarr.json"
  }
  if prefix == "" {
    Some(name)
  } else {
    Some("\{prefix}/\{name}")
  }
}

///|
/// Key for a chunk of a regular-grid array. Out-of-range coordinates are
/// rejected so callers cannot silently read/write a different chunk.
pub fn chunk_key(
  metadata : ArrayMetadata,
  coordinates : Array[Int],
  path : String,
) -> String? {
  if coordinates.length() != metadata.shape.length() {
    return None
  }
  guard normalized_path(path, metadata.format) is Some(prefix) else {
    return None
  }
  let mut key = if metadata.format == V3 && metadata.key_encoding == "default" {
    "c"
  } else {
    ""
  }
  for i in 0..<coordinates.length() {
    let coord = coordinates[i]
    let dim = metadata.shape[i]
    let chunk = metadata.chunk_shape[i]
    if dim == 0 || coord < 0 || coord > (dim - 1) / chunk {
      return None
    }
    if key == "" {
      key = "\{coord}"
    } else {
      key = "\{key}\{metadata.separator}\{coord}"
    }
  }
  if key == "" {
    key = "0"
  }
  if prefix == "" {
    Some(key)
  } else {
    Some("\{prefix}/\{key}")
  }
}
