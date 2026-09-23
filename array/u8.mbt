///|
/// An uncompressed uint8 array backed by MemoryStore. This is the first
/// typed slice of the future format-neutral array API.
pub struct U8Array {
  store : @store.MemoryStore
  metadata : @metadata.ArrayMetadata
  path : String
  fill : Byte
  chunk_len : Int
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
  guard @chunk.array_metadata_key(metadata.format, path) is Some(_) else {
    return None
  }
  if metadata.shape.length() != metadata.chunk_shape.length() {
    return None
  }
  if !@codec.is_plain_u8(metadata) {
    return None
  }
  guard @dtype.u8_fill(metadata.fill_value) is Some(fill) else { return None }
  guard @chunk.chunk_element_count(metadata) is Some(chunk_len) else {
    return None
  }
  Some({ store, metadata, path, fill, chunk_len })
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
      if bytes.length() != self.chunk_len {
        return None
      }
      Some(bytes[offset])
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
  let encoded = match self.store.get(key) {
    None => Bytes::make(self.chunk_len, self.fill)
    Some(bytes) => {
      if bytes.length() != self.chunk_len {
        return false
      }
      bytes
    }
  }
  let mutable = encoded.to_array()
  mutable[offset] = value
  self.store.put(key, Bytes::from_array(mutable[:]))
  true
}

///|
fn region_len(
  metadata : @metadata.ArrayMetadata,
  origin : Array[Int],
  extent : Array[Int],
) -> Int? {
  if origin.length() != metadata.shape.length() ||
    extent.length() != metadata.shape.length() {
    return None
  }
  let mut empty = false
  for i in 0..<origin.length() {
    let start = origin[i]
    let count = extent[i]
    let size = metadata.shape[i]
    if start < 0 || count < 0 || start > size || count > size - start {
      return None
    }
    if count == 0 {
      empty = true
    }
  }
  if empty {
    return Some(0)
  }
  let mut length = 1
  for count in extent {
    if length > 2147483647 / count {
      return None
    }
    length *= count
  }
  Some(length)
}

///|
fn region_coords(
  origin : Array[Int],
  extent : Array[Int],
  linear : Int,
) -> Array[Int] {
  let coords : Array[Int] = []
  for _ in 0..<origin.length() {
    coords.push(0)
  }
  let mut remainder = linear
  for reverse_i in 0..<origin.length() {
    let i = origin.length() - reverse_i - 1
    coords[i] = origin[i] + remainder % extent[i]
    remainder /= extent[i]
  }
  coords
}

///|
/// Read a bounded N-dimensional rectangle in C order. This works across
/// chunk boundaries without materializing the whole Zarr array.
pub fn U8Array::read_region(
  self : U8Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Bytes? {
  guard region_len(self.metadata, origin, extent) is Some(length) else {
    return None
  }
  let result = Bytes::make(length, b'\x00').to_array()
  for linear in 0..<length {
    guard self.read(region_coords(origin, extent, linear)) is Some(value) else {
      return None
    }
    result[linear] = value
  }
  Some(Bytes::from_array(result[:]))
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
  guard region_len(self.metadata, origin, extent) is Some(length) else {
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
