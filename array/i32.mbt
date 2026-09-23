///|
/// Uncompressed int32 array backed by a MemoryStore. Each operation touches
/// at most one full chunk; missing chunks return the declared fill value.
pub struct I32Array {
  store : @store.MemoryStore
  metadata : @metadata.ArrayMetadata
  path : String
  fill : Int
  chunk_bytes : Int
  big_endian : Bool
}

///|
pub fn open_i32(store : @store.MemoryStore, path : String) -> I32Array? {
  guard store.open_array(path) is Some(metadata) else { return None }
  open_i32_from_metadata(store, metadata, path)
}

///|
pub fn open_i32_from_metadata(
  store : @store.MemoryStore,
  metadata : @metadata.ArrayMetadata,
  path : String,
) -> I32Array? {
  guard @chunk.array_metadata_key(metadata.format, path) is Some(_) else {
    return None
  }
  guard @codec.plain_i32_endian(metadata) is Some(big_endian) else {
    return None
  }
  guard @dtype.i32_fill(metadata.fill_value) is Some(fill) else { return None }
  guard @chunk.chunk_element_count(metadata) is Some(count) else { return None }
  if count > 2147483647 / 4 {
    return None
  }
  Some({ store, metadata, path, fill, chunk_bytes: count * 4, big_endian })
}

///|
fn i32_bytes(value : Int, big_endian : Bool) -> Bytes {
  let bits = value.reinterpret_as_uint()
  let result = Bytes::make(4, b'\x00').to_array()
  for i in 0..<4 {
    let shift = if big_endian { (3 - i) * 8 } else { i * 8 }
    result[i] = (bits >> shift).to_byte()
  }
  Bytes::from_array(result[:])
}

///|
fn I32Array::encoded_fill(self : I32Array) -> Bytes {
  let element = i32_bytes(self.fill, self.big_endian)
  let result = Bytes::make(self.chunk_bytes, b'\x00').to_array()
  for offset in 0..<self.chunk_bytes {
    result[offset] = element[offset % 4]
  }
  Bytes::from_array(result[:])
}

///|
pub fn I32Array::read(self : I32Array, indices : Array[Int]) -> Int? {
  guard @chunk.element_location(self.metadata, indices, self.path)
    is Some((key, offset)) else {
    return None
  }
  match self.store.get(key) {
    None => Some(self.fill)
    Some(bytes) => {
      if bytes.length() != self.chunk_bytes {
        return None
      }
      let value = bytes.view(start=offset * 4, end=offset * 4 + 4)
      if self.big_endian {
        guard value is [u32be(bits), ..] else { return None }
        Some(bits.reinterpret_as_int())
      } else {
        guard value is [u32le(bits), ..] else { return None }
        Some(bits.reinterpret_as_int())
      }
    }
  }
}

///|
pub fn I32Array::write(
  self : I32Array,
  indices : Array[Int],
  value : Int,
) -> Bool {
  guard @chunk.element_location(self.metadata, indices, self.path)
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
  let value_bytes = i32_bytes(value, self.big_endian)
  let mutable = encoded.to_array()
  for i in 0..<4 {
    mutable[offset * 4 + i] = value_bytes[i]
  }
  self.store.put(key, Bytes::from_array(mutable[:]))
  true
}

///|
/// Read a bounded N-dimensional rectangle in C order across chunk boundaries.
pub fn I32Array::read_region(
  self : I32Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[Int]? {
  guard @chunk.region_len(self.metadata, origin, extent) is Some(length) else {
    return None
  }
  let result : Array[Int] = []
  for linear in 0..<length {
    guard self.read(@chunk.region_coords(origin, extent, linear)) is Some(value) else {
      return None
    }
    result.push(value)
  }
  Some(result)
}

///|
/// Write a C-order rectangle. Writes spanning multiple chunks are not atomic.
pub fn I32Array::write_region(
  self : I32Array,
  origin : Array[Int],
  extent : Array[Int],
  values : Array[Int],
) -> Bool {
  guard @chunk.region_len(self.metadata, origin, extent) is Some(length) else {
    return false
  }
  if values.length() != length {
    return false
  }
  for linear in 0..<length {
    if !self.write(@chunk.region_coords(origin, extent, linear), values[linear]) {
      return false
    }
  }
  true
}
