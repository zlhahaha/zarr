///|
/// Read a bounded C-order int64 rectangle across native filesystem chunks.
pub async fn FileI64Array::read_region(
  self : FileI64Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[Int64]? {
  guard @chunk.region_len(self.metadata, origin, extent) is Some(length) else {
    return None
  }
  guard @chunk.region_chunks(self.metadata, origin, extent) is Some(pieces) else {
    return None
  }
  let result : Array[Int64] = Array::make(length, 0L)
  for piece in pieces {
    let scratch = @store.MemoryStore::new()
    guard @array.open_i64_bits_from_metadata(scratch, self.metadata, self.path)
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
/// Writes spanning chunks are not atomic.
pub async fn FileI64Array::write_region(
  self : FileI64Array,
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
  guard @chunk.region_chunks(self.metadata, origin, extent) is Some(pieces) else {
    return false
  }
  for piece in pieces {
    let scratch = @store.MemoryStore::new()
    guard @array.open_i64_bits_from_metadata(scratch, self.metadata, self.path)
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
    let piece_values : Array[Int64] = []
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
