///|
/// Native filesystem view of a uint8 Zarr array. Operations
/// load one chunk at a time; cross-chunk writes are not yet transactional.
pub struct FileU8Array {
  store : FileStore
  metadata : @metadata.ArrayMetadata
  path : String
}

///|
pub async fn FileStore::open_u8(
  self : FileStore,
  path : String,
) -> FileU8Array? {
  guard self.open_array(path) is Some(metadata) else { return None }
  let scratch = @store.MemoryStore::new()
  guard @array.open_u8_from_metadata(scratch, metadata, path) is Some(_) else {
    return None
  }
  Some({ store: self, metadata, path, })
}

///|
fn FileU8Array::chunk_coords(
  self : FileU8Array,
  indices : Array[Int],
) -> Array[Int]? {
  if indices.length() != self.metadata.shape.length() {
    return None
  }
  let coordinates : Array[Int] = []
  for i in 0..<indices.length() {
    let index = indices[i]
    if index < 0 || index >= self.metadata.shape[i] {
      return None
    }
    coordinates.push(index / self.metadata.chunk_shape[i])
  }
  Some(coordinates)
}

///|
/// Read one element; missing chunks yield the metadata fill value.
pub async fn FileU8Array::read(
  self : FileU8Array,
  indices : Array[Int],
) -> Byte? {
  guard self.chunk_coords(indices) is Some(coordinates) else { return None }
  let scratch = @store.MemoryStore::new()
  guard @array.open_u8_bits_from_metadata(scratch, self.metadata, self.path)
    is Some(array) else {
    return None
  }
  match self.store.get_chunk(self.metadata, coordinates, self.path) {
    Some(bytes) =>
      if !scratch.put_chunk(self.metadata, coordinates, self.path, bytes) {
        return None
      }
    None => ()
  }
  array.read(indices)
}

///|
/// Write one element, persisting its full encoded chunk to the filesystem.
pub async fn FileU8Array::write(
  self : FileU8Array,
  indices : Array[Int],
  value : Byte,
) -> Bool {
  guard self.chunk_coords(indices) is Some(coordinates) else { return false }
  let scratch = @store.MemoryStore::new()
  guard @array.open_u8_bits_from_metadata(scratch, self.metadata, self.path)
    is Some(array) else {
    return false
  }
  match self.store.get_chunk(self.metadata, coordinates, self.path) {
    Some(bytes) =>
      if !scratch.put_chunk(self.metadata, coordinates, self.path, bytes) {
        return false
      }
    None => ()
  }
  if !array.write(indices, value) {
    return false
  }
  guard scratch.get_chunk(self.metadata, coordinates, self.path)
    is Some(encoded) else {
    return false
  }
  self.store.put_chunk(self.metadata, coordinates, self.path, encoded)
}
