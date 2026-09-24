///|
/// A boolean Zarr array backed by MemoryStore. Stored bytes are normalized
/// to 0 or 1 on write; a nonzero stored byte reads as true.
pub struct BoolArray {
  store : @store.MemoryStore
  metadata : @metadata.ArrayMetadata
  path : String
  fill : Bool
  chunk_len : Int
  compression : @codec.Compression
}

///|
pub fn open_bool(store : @store.MemoryStore, path : String) -> BoolArray? {
  guard store.open_array(path) is Some(metadata) else { return None }
  open_bool_from_metadata(store, metadata, path)
}

///|
pub fn open_bool_from_metadata(
  store : @store.MemoryStore,
  metadata : @metadata.ArrayMetadata,
  path : String,
) -> BoolArray? {
  guard @chunk.array_metadata_key(metadata.format, path) is Some(_) else {
    return None
  }
  guard @codec.bool_compression(metadata) is Some(compression) else {
    return None
  }
  guard @dtype.bool_fill(metadata.fill_value) is Some(fill) else { return None }
  guard @chunk.chunk_element_count(metadata) is Some(chunk_len) else {
    return None
  }
  Some({ store, metadata, path, fill, chunk_len, compression, })
}

///|
fn bool_byte(value : Bool) -> Byte {
  if value {
    b'\x01'
  } else {
    b'\x00'
  }
}

///|
pub fn BoolArray::read(self : BoolArray, indices : Array[Int]) -> Bool? {
  guard @chunk.element_location(self.metadata, indices, self.path)
    is Some((key, offset)) else {
    return None
  }
  match self.store.get(key) {
    None => Some(self.fill)
    Some(encoded) => {
      guard @codec.decode_chunk(self.compression, encoded, self.chunk_len)
        is Some(raw) else {
        return None
      }
      Some(raw[offset] != b'\x00')
    }
  }
}

///|
pub fn BoolArray::write(
  self : BoolArray,
  indices : Array[Int],
  value : Bool,
) -> Bool {
  guard @chunk.element_location(self.metadata, indices, self.path)
    is Some((key, offset)) else {
    return false
  }
  let raw = match self.store.get(key) {
    None => Bytes::make(self.chunk_len, bool_byte(self.fill))
    Some(encoded) => {
      guard @codec.decode_chunk(self.compression, encoded, self.chunk_len)
        is Some(decoded) else {
        return false
      }
      decoded
    }
  }
  let mutable = raw.to_array()
  mutable[offset] = bool_byte(value)
  guard @codec.encode_chunk(self.compression, Bytes::from_array(mutable[:]))
    is Some(encoded) else {
    return false
  }
  self.store.put(key, encoded)
  true
}

///|
/// Read a bounded rectangle in C order. Missing chunks use the fill value.
pub fn BoolArray::read_region(
  self : BoolArray,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[Bool]? {
  guard read_region_bytes(
      self.store,
      self.metadata,
      self.path,
      self.compression,
      self.chunk_len,
      Bytes::make(1, bool_byte(self.fill)),
      1,
      origin,
      extent,
    )
    is Some(bytes) else {
    return None
  }
  let values : Array[Bool] = []
  for byte in bytes {
    values.push(byte != b'\x00')
  }
  Some(values)
}

///|
/// Write a C-order rectangle. Cross-chunk writes are not atomic.
pub fn BoolArray::write_region(
  self : BoolArray,
  origin : Array[Int],
  extent : Array[Int],
  values : Array[Bool],
) -> Bool {
  let bytes : Array[Byte] = []
  for value in values {
    bytes.push(bool_byte(value))
  }
  write_region_bytes(
    self.store,
    self.metadata,
    self.path,
    self.compression,
    self.chunk_len,
    Bytes::make(1, bool_byte(self.fill)),
    1,
    origin,
    extent,
    Bytes::from_array(bytes),
  )
}
