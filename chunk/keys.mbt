///|
pub fn normalized_path(path : String, format : @metadata.Format) -> String? {
  let mut result = ""
  for part in path.replace_all(old="\\", new="/").split("/") {
    let segment = "\{part}"
    if segment != "" {
      if segment == "." || segment == ".." {
        return None
      }
      if format == @metadata.V3 &&
        (segment.has_prefix("__") || segment == "zarr.json") {
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
pub fn array_metadata_key(format : @metadata.Format, path : String) -> String? {
  guard normalized_path(path, format) is Some(prefix) else { return None }
  let name = match format {
    @metadata.V2 => ".zarray"
    @metadata.V3 => "zarr.json"
  }
  if prefix == "" {
    Some(name)
  } else {
    Some("\{prefix}/\{name}")
  }
}

///|
pub fn group_metadata_key(format : @metadata.Format, path : String) -> String? {
  guard normalized_path(path, format) is Some(prefix) else { return None }
  let name = if format == @metadata.V2 { ".zgroup" } else { "zarr.json" }
  Some(if prefix == "" { name } else { "\{prefix}/\{name}" })
}

///|
pub fn attributes_key(format : @metadata.Format, path : String) -> String? {
  if format != @metadata.V2 {
    return None
  }
  guard normalized_path(path, format) is Some(prefix) else { return None }
  Some(if prefix == "" { ".zattrs" } else { "\{prefix}/.zattrs" })
}

///|
/// Key for a chunk of a regular-grid array. Out-of-range coordinates are
/// rejected so callers cannot silently read/write a different chunk.
pub fn chunk_key(
  metadata : @metadata.ArrayMetadata,
  coordinates : Array[Int],
  path : String,
) -> String? {
  if coordinates.length() != metadata.shape.length() ||
    coordinates.length() != metadata.chunk_shape.length() {
    return None
  }
  guard normalized_path(path, metadata.format) is Some(prefix) else {
    return None
  }
  let mut key = if metadata.format == @metadata.V3 &&
    metadata.key_encoding == "default" {
    "c"
  } else {
    ""
  }
  for i in 0..<coordinates.length() {
    let coord = coordinates[i]
    let dim = metadata.shape[i]
    let chunk = metadata.chunk_shape[i]
    if chunk <= 0 || dim == 0 || coord < 0 || coord > (dim - 1) / chunk {
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

///|
/// Number of elements in one full chunk, or None if the size overflows Int.
pub fn chunk_element_count(metadata : @metadata.ArrayMetadata) -> Int? {
  if metadata.shape.length() != metadata.chunk_shape.length() {
    return None
  }
  let mut count = 1
  for side in metadata.chunk_shape {
    if side <= 0 || count > 2147483647 / side {
      return None
    }
    count *= side
  }
  Some(count)
}

///|
/// Locate an array element as its chunk key and element offset within a
/// full chunk. V2 F-order is honored; V3 uses C-order unless a transpose
/// codec is processed separately by a higher-level reader.
pub fn element_location(
  metadata : @metadata.ArrayMetadata,
  indices : Array[Int],
  path : String,
) -> (String, Int)? {
  guard chunk_element_count(metadata) is Some(_) else { return None }
  if indices.length() != metadata.shape.length() {
    return None
  }
  let chunk_coords : Array[Int] = []
  let local_coords : Array[Int] = []
  for i in 0..<indices.length() {
    let index = indices[i]
    if index < 0 || index >= metadata.shape[i] {
      return None
    }
    chunk_coords.push(index / metadata.chunk_shape[i])
    local_coords.push(index % metadata.chunk_shape[i])
  }
  guard chunk_key(metadata, chunk_coords, path) is Some(key) else {
    return None
  }
  let mut offset = 0
  if metadata.order == "F" {
    let mut stride = 1
    for i in 0..<local_coords.length() {
      offset += local_coords[i] * stride
      stride *= metadata.chunk_shape[i]
    }
  } else {
    for i in 0..<local_coords.length() {
      offset = offset * metadata.chunk_shape[i] + local_coords[i]
    }
  }
  Some((key, offset))
}
