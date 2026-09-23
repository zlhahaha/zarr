///|
/// Float64 array backed by a MemoryStore. Each operation touches
/// at most one full chunk; missing chunks return the declared fill value.
pub struct F64Array {
  store : @store.MemoryStore
  metadata : @metadata.ArrayMetadata
  path : String
  fill : Double
  chunk_bytes : Int
  big_endian : Bool
  compression : @codec.Compression
}

///|
pub fn open_f64(store : @store.MemoryStore, path : String) -> F64Array? {
  guard store.open_array(path) is Some(metadata) else { return None }
  open_f64_from_metadata(store, metadata, path)
}

///|
pub fn open_f64_from_metadata(
  store : @store.MemoryStore,
  metadata : @metadata.ArrayMetadata,
  path : String,
) -> F64Array? {
  guard @chunk.array_metadata_key(metadata.format, path) is Some(_) else {
    return None
  }
  guard @codec.f64_plan(metadata) is Some((big_endian, compression)) else {
    return None
  }
  guard @dtype.f64_fill(metadata.fill_value) is Some(fill) else { return None }
  guard @chunk.chunk_element_count(metadata) is Some(count) else { return None }
  if count > 2147483647 / 8 {
    return None
  }
  Some({
    store,
    metadata,
    path,
    fill,
    chunk_bytes: count * 8,
    big_endian,
    compression,
  })
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
      let value = raw.view(start=offset * 8, end=offset * 8 + 8)
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
  let value_bytes = if self.big_endian {
    value.reinterpret_as_uint64().to_be_bytes()
  } else {
    value.reinterpret_as_uint64().to_le_bytes()
  }
  let mutable = raw.to_array()
  for i in 0..<8 {
    mutable[offset * 8 + i] = value_bytes[i]
  }
  self.store.put(
    key,
    @codec.encode_chunk(self.compression, Bytes::from_array(mutable[:])),
  )
  true
}

///|
/// Read a bounded N-dimensional rectangle in C order across chunk boundaries.
pub fn F64Array::read_region(
  self : F64Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[Double]? {
  guard @chunk.region_len(self.metadata, origin, extent) is Some(length) else {
    return None
  }
  let result : Array[Double] = []
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
pub fn F64Array::write_region(
  self : F64Array,
  origin : Array[Int],
  extent : Array[Int],
  values : Array[Double],
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
