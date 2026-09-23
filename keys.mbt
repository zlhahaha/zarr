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
  if coordinates.length() != metadata.shape.length() ||
    coordinates.length() != metadata.chunk_shape.length() {
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
pub fn ArrayMetadata::chunk_element_count(self : ArrayMetadata) -> Int? {
  if self.shape.length() != self.chunk_shape.length() {
    return None
  }
  let mut count = 1
  for side in self.chunk_shape {
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
pub fn ArrayMetadata::element_location(
  self : ArrayMetadata,
  indices : Array[Int],
  path : String,
) -> (String, Int)? {
  guard self.chunk_element_count() is Some(_) else { return None }
  if indices.length() != self.shape.length() {
    return None
  }
  let chunk_coords : Array[Int] = []
  let local_coords : Array[Int] = []
  for i in 0..<indices.length() {
    let index = indices[i]
    if index < 0 || index >= self.shape[i] {
      return None
    }
    chunk_coords.push(index / self.chunk_shape[i])
    local_coords.push(index % self.chunk_shape[i])
  }
  guard chunk_key(self, chunk_coords, path) is Some(key) else { return None }
  let mut offset = 0
  if self.order == "F" {
    let mut stride = 1
    for i in 0..<local_coords.length() {
      offset += local_coords[i] * stride
      stride *= self.chunk_shape[i]
    }
  } else {
    for i in 0..<local_coords.length() {
      offset = offset * self.chunk_shape[i] + local_coords[i]
    }
  }
  Some((key, offset))
}
