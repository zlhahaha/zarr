///|
/// Read a bounded C-order uint8 rectangle across native filesystem chunks.
pub async fn FileU8Array::read_region(
  self : FileU8Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Bytes? {
  guard @chunk.region_len(self.metadata, origin, extent) is Some(length) else {
    return None
  }
  guard @chunk.region_chunks(self.metadata, origin, extent) is Some(pieces) else {
    return None
  }
  let result = Bytes::make(length, b'\x00').to_array()
  for piece in pieces {
    let scratch = @store.MemoryStore::new()
    guard @array.open_u8_from_metadata(scratch, self.metadata, self.path)
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
    for linear in 0..<piece_len {
      let indices = @chunk.region_coords(piece.origin, piece.extent, linear)
      guard array.read(indices) is Some(value) else { return None }
      guard @chunk.region_index(origin, extent, indices) is Some(index) else {
        return None
      }
      result[index] = value
    }
  }
  Some(Bytes::from_array(result[:]))
}

///|
/// Writes spanning chunks are not atomic.
pub async fn FileU8Array::write_region(
  self : FileU8Array,
  origin : Array[Int],
  extent : Array[Int],
  values : Bytes,
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
    guard @array.open_u8_from_metadata(scratch, self.metadata, self.path)
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
    for linear in 0..<piece_len {
      let indices = @chunk.region_coords(piece.origin, piece.extent, linear)
      guard @chunk.region_index(origin, extent, indices) is Some(index) else {
        return false
      }
      if !array.write(indices, values[index]) {
        return false
      }
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

///|
/// Read a bounded C-order float32 rectangle across native filesystem chunks.
pub async fn FileF32Array::read_region(
  self : FileF32Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[Float]? {
  guard @chunk.region_len(self.metadata, origin, extent) is Some(length) else {
    return None
  }
  guard @chunk.region_chunks(self.metadata, origin, extent) is Some(pieces) else {
    return None
  }
  let result : Array[Float] = Array::make(length, 0.0)
  for piece in pieces {
    let scratch = @store.MemoryStore::new()
    guard @array.open_f32_from_metadata(scratch, self.metadata, self.path)
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
    for linear in 0..<piece_len {
      let indices = @chunk.region_coords(piece.origin, piece.extent, linear)
      guard array.read(indices) is Some(value) else { return None }
      guard @chunk.region_index(origin, extent, indices) is Some(index) else {
        return None
      }
      result[index] = value
    }
  }
  Some(result)
}

///|
/// Writes spanning chunks are not atomic.
pub async fn FileF32Array::write_region(
  self : FileF32Array,
  origin : Array[Int],
  extent : Array[Int],
  values : Array[Float],
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
    guard @array.open_f32_from_metadata(scratch, self.metadata, self.path)
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
    for linear in 0..<piece_len {
      let indices = @chunk.region_coords(piece.origin, piece.extent, linear)
      guard @chunk.region_index(origin, extent, indices) is Some(index) else {
        return false
      }
      if !array.write(indices, values[index]) {
        return false
      }
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

///|
/// Read a bounded C-order float64 rectangle across native filesystem chunks.
pub async fn FileF64Array::read_region(
  self : FileF64Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[Double]? {
  guard @chunk.region_len(self.metadata, origin, extent) is Some(length) else {
    return None
  }
  guard @chunk.region_chunks(self.metadata, origin, extent) is Some(pieces) else {
    return None
  }
  let result : Array[Double] = Array::make(length, 0.0)
  for piece in pieces {
    let scratch = @store.MemoryStore::new()
    guard @array.open_f64_from_metadata(scratch, self.metadata, self.path)
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
    for linear in 0..<piece_len {
      let indices = @chunk.region_coords(piece.origin, piece.extent, linear)
      guard array.read(indices) is Some(value) else { return None }
      guard @chunk.region_index(origin, extent, indices) is Some(index) else {
        return None
      }
      result[index] = value
    }
  }
  Some(result)
}

///|
/// Writes spanning chunks are not atomic.
pub async fn FileF64Array::write_region(
  self : FileF64Array,
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
  guard @chunk.region_chunks(self.metadata, origin, extent) is Some(pieces) else {
    return false
  }
  for piece in pieces {
    let scratch = @store.MemoryStore::new()
    guard @array.open_f64_from_metadata(scratch, self.metadata, self.path)
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
    for linear in 0..<piece_len {
      let indices = @chunk.region_coords(piece.origin, piece.extent, linear)
      guard @chunk.region_index(origin, extent, indices) is Some(index) else {
        return false
      }
      if !array.write(indices, values[index]) {
        return false
      }
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

///|
/// Read a bounded C-order int32 rectangle across native filesystem chunks.
pub async fn FileI32Array::read_region(
  self : FileI32Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[Int]? {
  guard @chunk.region_len(self.metadata, origin, extent) is Some(length) else {
    return None
  }
  guard @chunk.region_chunks(self.metadata, origin, extent) is Some(pieces) else {
    return None
  }
  let result : Array[Int] = Array::make(length, 0)
  for piece in pieces {
    let scratch = @store.MemoryStore::new()
    guard @array.open_i32_from_metadata(scratch, self.metadata, self.path)
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
    for linear in 0..<piece_len {
      let indices = @chunk.region_coords(piece.origin, piece.extent, linear)
      guard array.read(indices) is Some(value) else { return None }
      guard @chunk.region_index(origin, extent, indices) is Some(index) else {
        return None
      }
      result[index] = value
    }
  }
  Some(result)
}

///|
/// Writes spanning chunks are not atomic.
pub async fn FileI32Array::write_region(
  self : FileI32Array,
  origin : Array[Int],
  extent : Array[Int],
  values : Array[Int],
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
    guard @array.open_i32_from_metadata(scratch, self.metadata, self.path)
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
    for linear in 0..<piece_len {
      let indices = @chunk.region_coords(piece.origin, piece.extent, linear)
      guard @chunk.region_index(origin, extent, indices) is Some(index) else {
        return false
      }
      if !array.write(indices, values[index]) {
        return false
      }
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
