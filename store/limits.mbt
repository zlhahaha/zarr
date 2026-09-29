///|
/// Input/work budgets, not a bound on total process or heap memory.
pub struct ReadLimits {
  metadata_bytes : Int
  encoded_bytes : Int
  decoded_bytes : Int
  region_bytes : Int
  region_elements : Int
  chunks : Int
  rank : Int
  json_depth : Int
}

///|
pub fn ReadLimits::new(
  max_metadata_bytes? : Int = 1048576,
  max_chunk_bytes? : Int = 67108864,
  max_decoded_chunk_bytes? : Int = 67108864,
  max_region_bytes? : Int = 67108864,
  max_region_elements? : Int = 8388608,
  max_chunks? : Int = 16384,
  max_rank? : Int = 64,
  max_json_depth? : Int = 64,
) -> ReadLimits? {
  if max_metadata_bytes <= 0 ||
    max_chunk_bytes <= 0 ||
    max_decoded_chunk_bytes <= 0 ||
    max_region_bytes <= 0 ||
    max_region_elements <= 0 ||
    max_chunks <= 0 ||
    max_rank <= 0 ||
    max_json_depth <= 0 {
    return None
  }
  Some({
    metadata_bytes: max_metadata_bytes,
    encoded_bytes: max_chunk_bytes,
    decoded_bytes: max_decoded_chunk_bytes,
    region_bytes: max_region_bytes,
    region_elements: max_region_elements,
    chunks: max_chunks,
    rank: max_rank,
    json_depth: max_json_depth,
  })
}

///|
pub fn ReadLimits::defaults() -> ReadLimits {
  {
    metadata_bytes: 1048576,
    encoded_bytes: 67108864,
    decoded_bytes: 67108864,
    region_bytes: 67108864,
    region_elements: 8388608,
    chunks: 16384,
    rank: 64,
    json_depth: 64,
  }
}

///|
pub fn ReadLimits::max_metadata_bytes(self : ReadLimits) -> Int {
  self.metadata_bytes
}

///|
pub fn ReadLimits::max_chunk_bytes(self : ReadLimits) -> Int {
  self.encoded_bytes
}

///|
pub fn ReadLimits::max_chunks(self : ReadLimits) -> Int {
  self.chunks
}

///|
/// A constant-space ASCII structural scan before UTF-8 decoding / JSON parsing.
/// Brackets inside strings (including escaped quotes) do not count as nesting.
/// Full JSON syntax and UTF-8 validity are still checked by the real parser.
pub fn ReadLimits::allows_metadata(self : ReadLimits, bytes : Bytes) -> Bool {
  if bytes.length() > self.metadata_bytes {
    return false
  }
  let mut depth = 0
  let mut quoted = false
  let mut escaped = false
  for byte in bytes {
    if quoted {
      if escaped {
        escaped = false
      } else if byte == b'\\' {
        escaped = true
      } else if byte == b'"' {
        quoted = false
      }
    } else if byte == b'"' {
      quoted = true
    } else if byte == b'{' || byte == b'[' {
      if depth >= self.json_depth {
        return false
      }
      depth += 1
    } else if byte == b'}' || byte == b']' {
      if depth == 0 {
        return false
      }
      depth -= 1
    }
  }
  depth == 0 && !quoted
}

///|
/// Limits for metadata keys also apply to attributes and consolidated indexes.
pub fn ReadLimits::key_limit(self : ReadLimits, key : String) -> Int {
  if key == ".zarray" ||
    key.has_suffix("/.zarray") ||
    key == ".zgroup" ||
    key.has_suffix("/.zgroup") ||
    key == ".zattrs" ||
    key.has_suffix("/.zattrs") ||
    key == ".zmetadata" ||
    key.has_suffix("/.zmetadata") ||
    key == "zarr.json" ||
    key.has_suffix("/zarr.json") {
    self.metadata_bytes
  } else {
    self.encoded_bytes
  }
}

///|
fn element_bytes(metadata : @metadata.ArrayMetadata) -> Int? {
  match metadata.data_type {
    "bool" | "|b1" | "uint8" | "int8" | "|u1" | "|i1" => Some(1)
    "uint16" | "int16" | "<u2" | ">u2" | "<i2" | ">i2" => Some(2)
    "uint32"
    | "int32"
    | "float32"
    | "<u4"
    | ">u4"
    | "<i4"
    | ">i4"
    | "<f4"
    | ">f4" => Some(4)
    "uint64"
    | "int64"
    | "float64"
    | "<u8"
    | ">u8"
    | "<i8"
    | ">i8"
    | "<f8"
    | ">f8" => Some(8)
    _ => None
  }
}

///|
pub fn ReadLimits::allows_array(
  self : ReadLimits,
  metadata : @metadata.ArrayMetadata,
) -> Bool {
  if metadata.shape.length() > self.rank ||
    metadata.shape.length() != metadata.chunk_shape.length() {
    return false
  }
  guard element_bytes(metadata) is Some(width) else { return false }
  guard @chunk.chunk_element_count(metadata) is Some(count) else {
    return false
  }
  count <= self.decoded_bytes / width
}

///|
/// Checked products and chunk count only; never enumerate a region here.
pub fn ReadLimits::allows_region(
  self : ReadLimits,
  metadata : @metadata.ArrayMetadata,
  origin : Array[Int],
  extent : Array[Int],
) -> Bool {
  if !self.allows_array(metadata) {
    return false
  }
  guard element_bytes(metadata) is Some(width) else { return false }
  guard @chunk.region_len(metadata, origin, extent) is Some(count) else {
    return false
  }
  if count > self.region_elements || count > self.region_bytes / width {
    return false
  }
  guard @chunk.region_chunk_count(metadata, origin, extent) is Some(chunks) else {
    return false
  }
  chunks <= self.chunks
}

///|
pub fn ReadLimits::allows_decode(
  self : ReadLimits,
  encoded_bytes : Int,
  decoded_bytes : Int,
) -> Bool {
  encoded_bytes >= 0 &&
  encoded_bytes <= self.encoded_bytes &&
  decoded_bytes > 0 &&
  decoded_bytes <= self.decoded_bytes
}
