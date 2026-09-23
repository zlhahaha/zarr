///|
/// Float32 array backed by a MemoryStore. Each operation touches
/// at most one full chunk; missing chunks return the declared fill value.
pub struct F32Array {
  store : @store.MemoryStore
  metadata : @metadata.ArrayMetadata
  path : String
  fill : Float
  chunk_bytes : Int
  big_endian : Bool
  compression : @codec.Compression
}

///|
pub fn open_f32(store : @store.MemoryStore, path : String) -> F32Array? {
  guard store.open_array(path) is Some(metadata) else { return None }
  open_f32_from_metadata(store, metadata, path)
}

///|
pub fn open_f32_from_metadata(
  store : @store.MemoryStore,
  metadata : @metadata.ArrayMetadata,
  path : String,
) -> F32Array? {
  guard @chunk.array_metadata_key(metadata.format, path) is Some(_) else {
    return None
  }
  guard @codec.f32_plan(metadata) is Some((big_endian, compression)) else {
    return None
  }
  guard @dtype.f32_fill(metadata.fill_value) is Some(fill) else { return None }
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
fn f32_bytes(value : Float, big_endian : Bool) -> Bytes {
  let bits = value.reinterpret_as_uint()
  let result = Bytes::make(4, b'\x00').to_array()
  for i in 0..<4 {
    let shift = if big_endian { (3 - i) * 8 } else { i * 8 }
    result[i] = (bits >> shift).to_byte()
  }
  Bytes::from_array(result[:])
}

///|
fn F32Array::encoded_fill(self : F32Array) -> Bytes {
  let element = f32_bytes(self.fill, self.big_endian)
  let result = Bytes::make(self.chunk_bytes, b'\x00').to_array()
  for offset in 0..<self.chunk_bytes {
    result[offset] = element[offset % 4]
  }
  Bytes::from_array(result[:])
}

///|
pub fn F32Array::read(self : F32Array, indices : Array[Int]) -> Float? {
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
      let value = raw.view(start=offset * 4, end=offset * 4 + 4)
      if self.big_endian {
        guard value is [u32be(bits), ..] else { return None }
        Some(Float::reinterpret_from_uint(bits))
      } else {
        guard value is [u32le(bits), ..] else { return None }
        Some(Float::reinterpret_from_uint(bits))
      }
    }
  }
}

///|
pub fn F32Array::write(
  self : F32Array,
  indices : Array[Int],
  value : Float,
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
  let value_bytes = f32_bytes(value, self.big_endian)
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
pub fn F32Array::read_region(
  self : F32Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[Float]? {
  guard @chunk.region_len(self.metadata, origin, extent) is Some(length) else {
    return None
  }
  let result : Array[Float] = []
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
pub fn F32Array::write_region(
  self : F32Array,
  origin : Array[Int],
  extent : Array[Int],
  values : Array[Float],
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
