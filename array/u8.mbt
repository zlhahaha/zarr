///|
/// A uint8 array backed by MemoryStore.
pub struct U8Array {
  store : @store.MemoryStore
  metadata : @metadata.ArrayMetadata
  path : String
  fill : Byte
  chunk_len : Int
  compression : @codec.Compression
}

///|
/// Open a uint8 array only if all its encoding steps are implemented.
pub fn open_u8(store : @store.MemoryStore, path : String) -> U8Array? {
  guard store.open_array(path) is Some(metadata) else { return None }
  open_u8_from_metadata(store, metadata, path)
}

///|
/// Construct a uint8 view from metadata already loaded by another store.
/// The caller must ensure the metadata belongs to this logical path.
pub fn open_u8_from_metadata(
  store : @store.MemoryStore,
  metadata : @metadata.ArrayMetadata,
  path : String,
) -> U8Array? {
  guard @dtype.is_u8(metadata) else { return None }
  open_u8_bits_from_metadata(store, metadata, path)
}

///|
/// Shared one-byte storage path; typed openers check signedness first.
pub fn open_u8_bits_from_metadata(
  store : @store.MemoryStore,
  metadata : @metadata.ArrayMetadata,
  path : String,
) -> U8Array? {
  guard @chunk.array_metadata_key(metadata.format, path) is Some(_) else {
    return None
  }
  if metadata.shape.length() != metadata.chunk_shape.length() {
    return None
  }
  let (compression, fill) = if @codec.u8_compression(metadata) is Some(plan) {
    guard @dtype.u8_fill(metadata.fill_value) is Some(value) else {
      return None
    }
    (plan, value)
  } else if @codec.i8_compression(metadata) is Some(plan) {
    guard @dtype.i8_fill(metadata.fill_value) is Some(value) else {
      return None
    }
    (plan, (value & 255).to_byte())
  } else {
    return None
  }
  guard @chunk.chunk_element_count(metadata) is Some(chunk_len) else {
    return None
  }
  Some({ store, metadata, path, fill, chunk_len, compression, })
}

///|
fn U8Array::locate(self : U8Array, indices : Array[Int]) -> (String, Int)? {
  @chunk.element_location(self.metadata, indices, self.path)
}

///|
/// Read one element. A missing chunk yields the metadata fill value.
pub fn U8Array::read(self : U8Array, indices : Array[Int]) -> Byte? {
  guard self.locate(indices) is Some((key, offset)) else { return None }
  match self.store.get(key) {
    None => Some(self.fill)
    Some(bytes) => {
      guard @codec.decode_chunk(self.compression, bytes, self.chunk_len)
        is Some(raw) else {
        return None
      }
      Some(raw[offset])
    }
  }
}

///|
/// Write one element, materializing a full-sized chunk on first write.
pub fn U8Array::write(
  self : U8Array,
  indices : Array[Int],
  value : Byte,
) -> Bool {
  guard self.locate(indices) is Some((key, offset)) else { return false }
  let raw = match self.store.get(key) {
    None => Bytes::make(self.chunk_len, self.fill)
    Some(bytes) => {
      guard @codec.decode_chunk(self.compression, bytes, self.chunk_len)
        is Some(raw) else {
        return false
      }
      raw
    }
  }
  let mutable = raw.to_array()
  mutable[offset] = value
  guard @codec.encode_chunk(self.compression, Bytes::from_array(mutable[:]))
    is Some(encoded) else {
    return false
  }
  self.store.put(key, encoded)
  true
}

///|
/// Read a bounded N-dimensional rectangle in C order. This works across
/// chunk boundaries without materializing the whole Zarr array.
pub fn U8Array::read_region(
  self : U8Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Bytes? {
  read_region_bytes(
    self.store,
    self.metadata,
    self.path,
    self.compression,
    self.chunk_len,
    Bytes::make(1, self.fill),
    1,
    origin,
    extent,
  )
}

///|
/// Write a bounded rectangle from C-order bytes. A write spanning multiple
/// chunks is not atomic; an error in a later chunk may leave earlier writes.
pub fn U8Array::write_region(
  self : U8Array,
  origin : Array[Int],
  extent : Array[Int],
  values : Bytes,
) -> Bool {
  write_region_bytes(
    self.store,
    self.metadata,
    self.path,
    self.compression,
    self.chunk_len,
    Bytes::make(1, self.fill),
    1,
    origin,
    extent,
    values,
  )
}
