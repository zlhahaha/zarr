///|
/// Native filesystem view of a float64 Zarr array.
pub struct FileF64Array {
  store : FileStore
  metadata : @metadata.ArrayMetadata
  path : String
}

///|
pub async fn FileStore::open_f64(
  self : FileStore,
  path : String,
) -> FileF64Array? {
  guard self.open_array(path) is Some(metadata) else { return None }
  let scratch = @store.MemoryStore::new()
  guard @array.open_f64_from_metadata(scratch, metadata, path) is Some(_) else {
    return None
  }
  Some({ store: self, metadata, path })
}

///|
fn FileF64Array::chunk_coords(
  self : FileF64Array,
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
pub async fn FileF64Array::read(
  self : FileF64Array,
  indices : Array[Int],
) -> Double? {
  guard self.chunk_coords(indices) is Some(coordinates) else { return None }
  let scratch = @store.MemoryStore::new()
  guard @array.open_f64_from_metadata(scratch, self.metadata, self.path)
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
pub async fn FileF64Array::write(
  self : FileF64Array,
  indices : Array[Int],
  value : Double,
) -> Bool {
  guard self.chunk_coords(indices) is Some(coordinates) else { return false }
  let scratch = @store.MemoryStore::new()
  guard @array.open_f64_from_metadata(scratch, self.metadata, self.path)
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
