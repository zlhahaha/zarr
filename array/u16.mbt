///|
/// Unsigned 16-bit array backed by MemoryStore.
pub struct U16Array {
  store : @store.MemoryStore
  metadata : @metadata.ArrayMetadata
  path : String
  fill : UInt16
  chunk_bytes : Int
  big_endian : Bool
  compression : @codec.Compression
}

///|
pub fn open_u16(store : @store.MemoryStore, path : String) -> U16Array? {
  guard store.open_array(path) is Some(metadata) else { return None }
  open_u16_from_metadata(store, metadata, path)
}

///|
pub fn open_u16_from_metadata(
  store : @store.MemoryStore,
  metadata : @metadata.ArrayMetadata,
  path : String,
) -> U16Array? {
  guard @chunk.array_metadata_key(metadata.format, path) is Some(_) else {
    return None
  }
  guard @codec.u16_plan(metadata) is Some((big_endian, compression)) else {
    return None
  }
  guard @dtype.u16_fill(metadata.fill_value) is Some(fill) else { return None }
  guard @chunk.chunk_element_count(metadata) is Some(count) else { return None }
  if count > 2147483647 / 2 {
    return None
  }
  Some({
    store,
    metadata,
    path,
    fill,
    chunk_bytes: count * 2,
    big_endian,
    compression,
  })
}

///|
fn u16_bytes(value : UInt16, big_endian : Bool) -> Bytes {
  let number = value.to_int()
  let bytes = Bytes::make(2, b'\x00').to_array()
  if big_endian {
    bytes[0] = (number >> 8).to_byte()
    bytes[1] = number.to_byte()
  } else {
    bytes[0] = number.to_byte()
    bytes[1] = (number >> 8).to_byte()
  }
  Bytes::from_array(bytes[:])
}

///|
fn U16Array::encoded_fill(self : U16Array) -> Bytes {
  let element = u16_bytes(self.fill, self.big_endian)
  let bytes = Bytes::make(self.chunk_bytes, b'\x00').to_array()
  for offset in 0..<self.chunk_bytes {
    bytes[offset] = element[offset % 2]
  }
  Bytes::from_array(bytes[:])
}

///|
pub fn U16Array::read(self : U16Array, indices : Array[Int]) -> UInt16? {
  guard @chunk.element_location(self.metadata, indices, self.path)
    is Some((key, offset)) else {
    return None
  }
  match self.store.get(key) {
    None => Some(self.fill)
    Some(encoded) => {
      guard @codec.decode_chunk(self.compression, encoded, self.chunk_bytes)
        is Some(raw) else {
        return None
      }
      let value = raw.view(start=offset * 2, end=offset * 2 + 2)
      if self.big_endian {
        guard value is [u16be(bits), ..] else { return None }
        Some(bits.to_uint16())
      } else {
        guard value is [u16le(bits), ..] else { return None }
        Some(bits.to_uint16())
      }
    }
  }
}

///|
pub fn U16Array::write(
  self : U16Array,
  indices : Array[Int],
  value : UInt16,
) -> Bool {
  guard @chunk.element_location(self.metadata, indices, self.path)
    is Some((key, offset)) else {
    return false
  }
  let raw = match self.store.get(key) {
    None => self.encoded_fill()
    Some(encoded) =>
      match @codec.decode_chunk(self.compression, encoded, self.chunk_bytes) {
        Some(decoded) => decoded
        None => return false
      }
  }
  let element = u16_bytes(value, self.big_endian)
  let bytes = raw.to_array()
  bytes[offset * 2] = element[0]
  bytes[offset * 2 + 1] = element[1]
  guard @codec.encode_chunk(self.compression, Bytes::from_array(bytes[:]))
    is Some(encoded) else {
    return false
  }
  self.store.put(key, encoded)
  true
}

///|
pub fn U16Array::read_region(
  self : U16Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[UInt16]? {
  guard read_region_bytes(
      self.store,
      self.metadata,
      self.path,
      self.compression,
      self.chunk_bytes,
      u16_bytes(self.fill, self.big_endian),
      2,
      origin,
      extent,
    )
    is Some(bytes) else {
    return None
  }
  let result : Array[UInt16] = []
  for linear in 0..<(bytes.length() / 2) {
    let value = bytes.view(start=linear * 2, end=linear * 2 + 2)
    if self.big_endian {
      guard value is [u16be(bits), ..] else { return None }
      result.push(bits.to_uint16())
    } else {
      guard value is [u16le(bits), ..] else { return None }
      result.push(bits.to_uint16())
    }
  }
  Some(result)
}

///|
pub fn U16Array::write_region(
  self : U16Array,
  origin : Array[Int],
  extent : Array[Int],
  values : Array[UInt16],
) -> Bool {
  guard @chunk.region_len(self.metadata, origin, extent) is Some(length) else {
    return false
  }
  if values.length() != length || length > 2147483647 / 2 {
    return false
  }
  let bytes = Bytes::make(length * 2, b'\x00').to_array()
  for linear in 0..<length {
    let element = u16_bytes(values[linear], self.big_endian)
    bytes[linear * 2] = element[0]
    bytes[linear * 2 + 1] = element[1]
  }
  write_region_bytes(
    self.store,
    self.metadata,
    self.path,
    self.compression,
    self.chunk_bytes,
    u16_bytes(self.fill, self.big_endian),
    2,
    origin,
    extent,
    Bytes::from_array(bytes[:]),
  )
}
