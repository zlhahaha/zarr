///|
/// Native filesystem view of a boolean Zarr array.
pub struct FileBoolArray {
  store : FileStore
  metadata : @metadata.ArrayMetadata
  path : String
}

///|
pub async fn FileStore::open_bool(
  self : FileStore,
  path : String,
) -> FileBoolArray? {
  guard self.open_array(path) is Some(metadata) else { return None }
  let scratch = @store.MemoryStore::new()
  guard @array.open_bool_from_metadata(scratch, metadata, path) is Some(_) else {
    return None
  }
  Some({ store: self, metadata, path, })
}

///|
fn FileBoolArray::chunk_coords(
  self : FileBoolArray,
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
pub async fn FileBoolArray::read(
  self : FileBoolArray,
  indices : Array[Int],
) -> Bool? {
  guard self.chunk_coords(indices) is Some(coordinates) else { return None }
  let scratch = @store.MemoryStore::new()
  guard @array.open_bool_from_metadata(scratch, self.metadata, self.path)
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
pub async fn FileBoolArray::write(
  self : FileBoolArray,
  indices : Array[Int],
  value : Bool,
) -> Bool {
  guard self.chunk_coords(indices) is Some(coordinates) else { return false }
  let scratch = @store.MemoryStore::new()
  guard @array.open_bool_from_metadata(scratch, self.metadata, self.path)
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

///|
/// Read a C-order rectangle, loading each touched filesystem chunk once.
pub async fn FileBoolArray::read_region(
  self : FileBoolArray,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[Bool]? {
  guard @chunk.region_len(self.metadata, origin, extent) is Some(length) else {
    return None
  }
  guard @chunk.region_chunks(self.metadata, origin, extent) is Some(pieces) else {
    return None
  }
  let result : Array[Bool] = Array::make(length, false)
  for piece in pieces {
    let scratch = @store.MemoryStore::new()
    guard @array.open_bool_from_metadata(scratch, self.metadata, self.path)
      is Some(array) else {
      return None
    }
    match self.store.get_chunk(self.metadata, piece.coordinates, self.path) {
      Some(bytes) =>
        if !scratch.put_chunk(
            self.metadata,
            piece.coordinates,
            self.path,
            bytes,
          ) {
          return None
        }
      None => ()
    }
    guard @chunk.region_len(self.metadata, piece.origin, piece.extent)
      is Some(piece_len) else {
      return None
    }
    guard array.read_region(piece.origin, piece.extent) is Some(piece_values) else {
      return None
    }
    for linear in 0..<piece_len {
      let indices = @chunk.region_coords(piece.origin, piece.extent, linear)
      guard @chunk.region_index(origin, extent, indices) is Some(index) else {
        return None
      }
      result[index] = piece_values[linear]
    }
  }
  Some(result)
}

///|
/// Cross-chunk writes are not atomic.
pub async fn FileBoolArray::write_region(
  self : FileBoolArray,
  origin : Array[Int],
  extent : Array[Int],
  values : Array[Bool],
) -> Bool {
  guard @chunk.region_len(self.metadata, origin, extent) is Some(length) else {
    return false
  }
  if values.length() != length {
    return false
  }
  guard @chunk.region_chunks(self.metadata, origin, extent) is Some(pieces) else {
    return false
  }
  for piece in pieces {
    let scratch = @store.MemoryStore::new()
    guard @array.open_bool_from_metadata(scratch, self.metadata, self.path)
      is Some(array) else {
      return false
    }
    match self.store.get_chunk(self.metadata, piece.coordinates, self.path) {
      Some(bytes) =>
        if !scratch.put_chunk(
            self.metadata,
            piece.coordinates,
            self.path,
            bytes,
          ) {
          return false
        }
      None => ()
    }
    guard @chunk.region_len(self.metadata, piece.origin, piece.extent)
      is Some(piece_len) else {
      return false
    }
    let piece_values : Array[Bool] = []
    for linear in 0..<piece_len {
      let indices = @chunk.region_coords(piece.origin, piece.extent, linear)
      guard @chunk.region_index(origin, extent, indices) is Some(index) else {
        return false
      }
      piece_values.push(values[index])
    }
    if !array.write_region(piece.origin, piece.extent, piece_values) {
      return false
    }
    guard scratch.get_chunk(self.metadata, piece.coordinates, self.path)
      is Some(encoded) else {
      return false
    }
    if !self.store.put_chunk(
        self.metadata,
        piece.coordinates,
        self.path,
        encoded,
      ) {
      return false
    }
  }
  true
}
