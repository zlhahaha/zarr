///|
/// Int32 array backed by a MemoryStore. Each operation touches
/// at most one full chunk; missing chunks return the declared fill value.
pub struct I32Array {
  store : @store.MemoryStore
  metadata : @metadata.ArrayMetadata
  path : String
  fill : Int
  chunk_bytes : Int
  big_endian : Bool
  compression : @codec.Compression
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
  guard @codec.i32_plan(metadata) is Some((big_endian, compression)) else {
    return None
  }
  guard @dtype.i32_fill(metadata.fill_value) is Some(fill) else { return None }
  guard @chunk.chunk_element_count(metadata) is Some(count) else { return None }
  if count > 2147483647 / 4 {
    return None
  }
  Some({
    store,
    metadata,
    path,
    fill,
    chunk_bytes: count * 4,
    big_endian,
    compression,
  })
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
      guard @codec.decode_chunk(self.compression, bytes, self.chunk_bytes)
        is Some(raw) else {
        return None
      }
      let value = raw[offset * 4:offset * 4 + 4]
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
  let raw = match self.store.get(key) {
    None => self.encoded_fill()
    Some(bytes) => {
      guard @codec.decode_chunk(self.compression, bytes, self.chunk_bytes)
        is Some(raw) else {
        return false
      }
      raw
    }
  }
  let value_bytes = i32_bytes(value, self.big_endian)
  let mutable = raw.to_array()
  for i in 0..<4 {
    mutable[offset * 4 + i] = value_bytes[i]
  }
  guard @codec.encode_chunk(self.compression, Bytes::from_array(mutable[:]))
    is Some(encoded) else {
    return false
  }
  self.store.put(key, encoded)
  true
}

///|
/// Read a bounded N-dimensional rectangle in C order across chunk boundaries.
pub fn I32Array::read_region(
  self : I32Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[Int]? {
  guard read_region_bytes(
      self.store,
      self.metadata,
      self.path,
      self.compression,
      self.chunk_bytes,
      i32_bytes(self.fill, self.big_endian),
      4,
      origin,
      extent,
    )
    is Some(bytes) else {
    return None
  }
  let result : Array[Int] = []
  for linear in 0..<(bytes.length() / 4) {
    let value = bytes[linear * 4:linear * 4 + 4]
    if self.big_endian {
      guard value is [u32be(bits), ..] else { return None }
      result.push(bits.reinterpret_as_int())
    } else {
      guard value is [u32le(bits), ..] else { return None }
      result.push(bits.reinterpret_as_int())
    }
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
  if length > 2147483647 / 4 {
    return false
  }
  let bytes = Bytes::make(length * 4, b'\x00').to_array()
  for linear in 0..<length {
    let element = i32_bytes(values[linear], self.big_endian)
    for i in 0..<4 {
      bytes[linear * 4 + i] = element[i]
    }
  }
  write_region_bytes(
    self.store,
    self.metadata,
    self.path,
    self.compression,
    self.chunk_bytes,
    i32_bytes(self.fill, self.big_endian),
    4,
    origin,
    extent,
    Bytes::from_array(bytes[:]),
  )
}
