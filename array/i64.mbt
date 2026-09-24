///|
/// Int64 array backed by a MemoryStore. Each operation touches
/// at most one full chunk; missing chunks return the declared fill value.
pub struct I64Array {
  store : @store.MemoryStore
  metadata : @metadata.ArrayMetadata
  path : String
  fill : Int64
  chunk_bytes : Int
  big_endian : Bool
  compression : @codec.Compression
}

///|
pub fn open_i64(store : @store.MemoryStore, path : String) -> I64Array? {
  guard store.open_array(path) is Some(metadata) else { return None }
  open_i64_from_metadata(store, metadata, path)
}

///|
pub fn open_i64_from_metadata(
  store : @store.MemoryStore,
  metadata : @metadata.ArrayMetadata,
  path : String,
) -> I64Array? {
  guard @dtype.i64_endian(metadata) is Some(_) else { return None }
  open_i64_bits_from_metadata(store, metadata, path)
}

///|
/// Shared eight-byte storage path; typed openers check signedness first.
pub fn open_i64_bits_from_metadata(
  store : @store.MemoryStore,
  metadata : @metadata.ArrayMetadata,
  path : String,
) -> I64Array? {
  guard @chunk.array_metadata_key(metadata.format, path) is Some(_) else {
    return None
  }
  let (big_endian, compression, fill) = if @codec.i64_plan(metadata)
    is Some((endian, plan)) {
    guard @dtype.i64_fill(metadata.fill_value) is Some(value) else {
      return None
    }
    (endian, plan, value)
  } else if @codec.u64_plan(metadata) is Some((endian, plan)) {
    guard @dtype.u64_fill(metadata.fill_value) is Some(value) else {
      return None
    }
    (endian, plan, value.reinterpret_as_int64())
  } else {
    return None
  }
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
fn I64Array::encoded_fill(self : I64Array) -> Bytes {
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
pub fn I64Array::read(self : I64Array, indices : Array[Int]) -> Int64? {
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
      let value = raw[offset * 8:offset * 8 + 8]
      if self.big_endian {
        guard value is [u64be(bits), ..] else { return None }
        Some(bits.reinterpret_as_int64())
      } else {
        guard value is [u64le(bits), ..] else { return None }
        Some(bits.reinterpret_as_int64())
      }
    }
  }
}

///|
pub fn I64Array::write(
  self : I64Array,
  indices : Array[Int],
  value : Int64,
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
  guard @codec.encode_chunk(self.compression, Bytes::from_array(mutable[:]))
    is Some(encoded) else {
    return false
  }
  self.store.put(key, encoded)
  true
}

///|
/// Read a bounded N-dimensional rectangle in C order across chunk boundaries.
pub fn I64Array::read_region(
  self : I64Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[Int64]? {
  let fill_element = if self.big_endian {
    self.fill.reinterpret_as_uint64().to_be_bytes()
  } else {
    self.fill.reinterpret_as_uint64().to_le_bytes()
  }
  guard read_region_bytes(
      self.store,
      self.metadata,
      self.path,
      self.compression,
      self.chunk_bytes,
      fill_element,
      8,
      origin,
      extent,
    )
    is Some(bytes) else {
    return None
  }
  let result : Array[Int64] = []
  for linear in 0..<(bytes.length() / 8) {
    let value = bytes[linear * 8:linear * 8 + 8]
    if self.big_endian {
      guard value is [u64be(bits), ..] else { return None }
      result.push(bits.reinterpret_as_int64())
    } else {
      guard value is [u64le(bits), ..] else { return None }
      result.push(bits.reinterpret_as_int64())
    }
  }
  Some(result)
}

///|
/// Write a C-order rectangle. Writes spanning multiple chunks are not atomic.
pub fn I64Array::write_region(
  self : I64Array,
  origin : Array[Int],
  extent : Array[Int],
  values : Array[Int64],
) -> Bool {
  guard @chunk.region_len(self.metadata, origin, extent) is Some(length) else {
    return false
  }
  if values.length() != length {
    return false
  }
  if length > 2147483647 / 8 {
    return false
  }
  let bytes = Bytes::make(length * 8, b'\x00').to_array()
  for linear in 0..<length {
    let element = if self.big_endian {
      values[linear].reinterpret_as_uint64().to_be_bytes()
    } else {
      values[linear].reinterpret_as_uint64().to_le_bytes()
    }
    for i in 0..<8 {
      bytes[linear * 8 + i] = element[i]
    }
  }
  let fill_element = if self.big_endian {
    self.fill.reinterpret_as_uint64().to_be_bytes()
  } else {
    self.fill.reinterpret_as_uint64().to_le_bytes()
  }
  write_region_bytes(
    self.store,
    self.metadata,
    self.path,
    self.compression,
    self.chunk_bytes,
    fill_element,
    8,
    origin,
    extent,
    Bytes::from_array(bytes[:]),
  )
}
