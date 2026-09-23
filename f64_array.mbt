///|
/// Uncompressed float64 array backed by a MemoryStore. Each operation touches
/// at most one full chunk; missing chunks return the declared fill value.
pub struct F64Array {
  store : MemoryStore
  metadata : ArrayMetadata
  path : String
  fill : Double
  chunk_bytes : Int
  big_endian : Bool
}

///|
fn plain_f64_endian(metadata : ArrayMetadata) -> Bool? {
  if metadata.storage_transformers.length() != 0 {
    return None
  }
  match metadata.format {
    V2 => {
      if metadata.codecs.length() != 0 {
        return None
      }
      match metadata.data_type {
        "<f8" => Some(false)
        ">f8" => Some(true)
        _ => None
      }
    }
    V3 => {
      if metadata.data_type != "float64" || metadata.codecs.length() != 1 {
        return None
      }
      guard metadata.codecs[0] is Object(codec) else { return None }
      guard codec.get("name") == Some(Json::string("bytes")) else {
        return None
      }
      guard codec.get("configuration") is Some(Object(config)) else {
        return None
      }
      match config.get("endian") {
        Some(String("little")) => Some(false)
        Some(String("big")) => Some(true)
        _ => None
      }
    }
  }
}

///|
fn f64_fill(value : Json) -> Double? {
  match value {
    Number(n, ..) => Some(n)
    _ => None
  }
}

///|
pub fn MemoryStore::open_f64(self : MemoryStore, path : String) -> F64Array? {
  guard self.open_array(path) is Some(metadata) else { return None }
  self.open_f64_from_metadata(metadata, path)
}

///|
pub fn MemoryStore::open_f64_from_metadata(
  self : MemoryStore,
  metadata : ArrayMetadata,
  path : String,
) -> F64Array? {
  guard array_metadata_key(metadata.format, path) is Some(_) else {
    return None
  }
  guard plain_f64_endian(metadata) is Some(big_endian) else { return None }
  guard f64_fill(metadata.fill_value) is Some(fill) else { return None }
  guard metadata.chunk_element_count() is Some(count) else { return None }
  if count > 2147483647 / 8 {
    return None
  }
  Some({ store: self, metadata, path, fill, chunk_bytes: count * 8, big_endian })
}

///|
fn F64Array::encoded_fill(self : F64Array) -> Bytes {
  let element = if self.big_endian {
    self.fill.reinterpret_as_uint64().to_be_bytes()
  } else {
    self.fill.reinterpret_as_uint64().to_le_bytes()
  }
  let result = Bytes::make(self.chunk_bytes, b'\x00').to_array()
  for offset in 0..<self.chunk_bytes {
    result[offset] = element[offset % 8]
  }
  Bytes::from_array(result[:])
}

///|
pub fn F64Array::read(self : F64Array, indices : Array[Int]) -> Double? {
  guard self.metadata.element_location(indices, self.path)
    is Some((key, offset)) else {
    return None
  }
  match self.store.get(key) {
    None => Some(self.fill)
    Some(bytes) => {
      if bytes.length() != self.chunk_bytes {
        return None
      }
      let value = bytes.view(start=offset * 8, end=offset * 8 + 8)
      if self.big_endian {
        guard value is [u64be(bits), ..] else { return None }
        Some(bits.reinterpret_as_double())
      } else {
        guard value is [u64le(bits), ..] else { return None }
        Some(bits.reinterpret_as_double())
      }
    }
  }
}

///|
pub fn F64Array::write(
  self : F64Array,
  indices : Array[Int],
  value : Double,
) -> Bool {
  guard self.metadata.element_location(indices, self.path)
    is Some((key, offset)) else {
    return false
  }
  let encoded = match self.store.get(key) {
    None => self.encoded_fill()
    Some(bytes) => {
      if bytes.length() != self.chunk_bytes {
        return false
      }
      bytes
    }
  }
  let value_bytes = if self.big_endian {
    value.reinterpret_as_uint64().to_be_bytes()
  } else {
    value.reinterpret_as_uint64().to_le_bytes()
  }
  let mutable = encoded.to_array()
  for i in 0..<8 {
    mutable[offset * 8 + i] = value_bytes[i]
  }
  self.store.put(key, Bytes::from_array(mutable[:]))
  true
}

///|
/// Read a bounded N-dimensional rectangle in C order across chunk boundaries.
pub fn F64Array::read_region(
  self : F64Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[Double]? {
  guard self.metadata.region_len(origin, extent) is Some(length) else {
    return None
  }
  let result : Array[Double] = []
  for linear in 0..<length {
    guard self.read(region_coords(origin, extent, linear)) is Some(value) else {
      return None
    }
    result.push(value)
  }
  Some(result)
}

///|
/// Write a C-order rectangle. Writes spanning multiple chunks are not atomic.
pub fn F64Array::write_region(
  self : F64Array,
  origin : Array[Int],
  extent : Array[Int],
  values : Array[Double],
) -> Bool {
  guard self.metadata.region_len(origin, extent) is Some(length) else {
    return false
  }
  if values.length() != length {
    return false
  }
  for linear in 0..<length {
    if !self.write(region_coords(origin, extent, linear), values[linear]) {
      return false
    }
  }
  true
}
