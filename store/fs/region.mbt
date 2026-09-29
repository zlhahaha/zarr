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
  if !self.store.limits.allows_region(self.metadata, origin, extent) {
    return None
  }
  guard @chunk.region_chunks(
      self.metadata,
      origin,
      extent,
      max_chunks=self.store.limits.max_chunks(),
    )
    is Some(pieces) else {
    return None
  }
  let result = Bytes::make(length, b'\x00').to_array()
  let reader = self.store.shard_session()
  for piece in pieces {
    let scratch = self.store.scratch()
    guard @array.open_u8_bits_from_metadata(scratch, self.metadata, self.path)
      is Some(array) else {
      return None
    }
    match reader.get_chunk(self.metadata, piece.coordinates, self.path) {
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
    guard array.read_region(piece.origin, piece.extent) is Some(piece_values) else {
      return None
    }
    if !@chunk.copy_region_spans(
        piece.origin,
        piece.extent,
        origin,
        extent,
        piece.origin,
        piece.extent,
        fn(source, destination, count, _stride) {
          for i in 0..<count {
            result[destination + i] = piece_values[source + i]
          }
        },
      ) {
      return None
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
  if !self.store.limits.allows_region(self.metadata, origin, extent) {
    return false
  }
  guard @chunk.region_chunks(
      self.metadata,
      origin,
      extent,
      max_chunks=self.store.limits.max_chunks(),
    )
    is Some(pieces) else {
    return false
  }
  for piece in pieces {
    let scratch = self.store.scratch()
    guard @array.open_u8_bits_from_metadata(scratch, self.metadata, self.path)
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
    let piece_values = Bytes::make(piece_len, b'\x00').to_array()
    for linear in 0..<piece_len {
      let indices = @chunk.region_coords(piece.origin, piece.extent, linear)
      guard @chunk.region_index(origin, extent, indices) is Some(index) else {
        return false
      }
      piece_values[linear] = values[index]
    }
    if !array.write_region(
        piece.origin,
        piece.extent,
        Bytes::from_array(piece_values[:]),
      ) {
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
  if !self.store.limits.allows_region(self.metadata, origin, extent) {
    return None
  }
  guard @chunk.region_chunks(
      self.metadata,
      origin,
      extent,
      max_chunks=self.store.limits.max_chunks(),
    )
    is Some(pieces) else {
    return None
  }
  let result : Array[Float] = Array::make(length, 0.0)
  let reader = self.store.shard_session()
  for piece in pieces {
    let scratch = self.store.scratch()
    guard @array.open_f32_from_metadata(scratch, self.metadata, self.path)
      is Some(array) else {
      return None
    }
    match reader.get_chunk(self.metadata, piece.coordinates, self.path) {
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
    guard array.read_region(piece.origin, piece.extent) is Some(piece_values) else {
      return None
    }
    if !@chunk.copy_region_spans(
        piece.origin,
        piece.extent,
        origin,
        extent,
        piece.origin,
        piece.extent,
        fn(source, destination, count, _stride) {
          for i in 0..<count {
            result[destination + i] = piece_values[source + i]
          }
        },
      ) {
      return None
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
  if !self.store.limits.allows_region(self.metadata, origin, extent) {
    return false
  }
  guard @chunk.region_chunks(
      self.metadata,
      origin,
      extent,
      max_chunks=self.store.limits.max_chunks(),
    )
    is Some(pieces) else {
    return false
  }
  for piece in pieces {
    let scratch = self.store.scratch()
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
    let piece_values : Array[Float] = []
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
  if !self.store.limits.allows_region(self.metadata, origin, extent) {
    return None
  }
  guard @chunk.region_chunks(
      self.metadata,
      origin,
      extent,
      max_chunks=self.store.limits.max_chunks(),
    )
    is Some(pieces) else {
    return None
  }
  let result : Array[Double] = Array::make(length, 0.0)
  let reader = self.store.shard_session()
  for piece in pieces {
    let scratch = self.store.scratch()
    guard @array.open_f64_from_metadata(scratch, self.metadata, self.path)
      is Some(array) else {
      return None
    }
    match reader.get_chunk(self.metadata, piece.coordinates, self.path) {
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
    guard array.read_region(piece.origin, piece.extent) is Some(piece_values) else {
      return None
    }
    if !@chunk.copy_region_spans(
        piece.origin,
        piece.extent,
        origin,
        extent,
        piece.origin,
        piece.extent,
        fn(source, destination, count, _stride) {
          for i in 0..<count {
            result[destination + i] = piece_values[source + i]
          }
        },
      ) {
      return None
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
  if !self.store.limits.allows_region(self.metadata, origin, extent) {
    return false
  }
  guard @chunk.region_chunks(
      self.metadata,
      origin,
      extent,
      max_chunks=self.store.limits.max_chunks(),
    )
    is Some(pieces) else {
    return false
  }
  for piece in pieces {
    let scratch = self.store.scratch()
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
    let piece_values : Array[Double] = []
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
  if !self.store.limits.allows_region(self.metadata, origin, extent) {
    return None
  }
  guard @chunk.region_chunks(
      self.metadata,
      origin,
      extent,
      max_chunks=self.store.limits.max_chunks(),
    )
    is Some(pieces) else {
    return None
  }
  let result : Array[Int] = Array::make(length, 0)
  let reader = self.store.shard_session()
  for piece in pieces {
    let scratch = self.store.scratch()
    guard @array.open_i32_bits_from_metadata(scratch, self.metadata, self.path)
      is Some(array) else {
      return None
    }
    match reader.get_chunk(self.metadata, piece.coordinates, self.path) {
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
    guard array.read_region(piece.origin, piece.extent) is Some(piece_values) else {
      return None
    }
    if !@chunk.copy_region_spans(
        piece.origin,
        piece.extent,
        origin,
        extent,
        piece.origin,
        piece.extent,
        fn(source, destination, count, _stride) {
          for i in 0..<count {
            result[destination + i] = piece_values[source + i]
          }
        },
      ) {
      return None
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
  if !self.store.limits.allows_region(self.metadata, origin, extent) {
    return false
  }
  guard @chunk.region_chunks(
      self.metadata,
      origin,
      extent,
      max_chunks=self.store.limits.max_chunks(),
    )
    is Some(pieces) else {
    return false
  }
  for piece in pieces {
    let scratch = self.store.scratch()
    guard @array.open_i32_bits_from_metadata(scratch, self.metadata, self.path)
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
    let piece_values : Array[Int] = []
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

///|
/// Read a C-order uint16 rectangle, loading each touched filesystem chunk once.
pub async fn FileU16Array::read_region(
  self : FileU16Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[UInt16]? {
  guard @chunk.region_len(self.metadata, origin, extent) is Some(length) else {
    return None
  }
  if !self.store.limits.allows_region(self.metadata, origin, extent) {
    return None
  }
  guard @chunk.region_chunks(
      self.metadata,
      origin,
      extent,
      max_chunks=self.store.limits.max_chunks(),
    )
    is Some(pieces) else {
    return None
  }
  let result : Array[UInt16] = Array::make(length, (0 : UInt16))
  let reader = self.store.shard_session()
  for piece in pieces {
    let scratch = self.store.scratch()
    guard @array.open_u16_bits_from_metadata(scratch, self.metadata, self.path)
      is Some(array) else {
      return None
    }
    match reader.get_chunk(self.metadata, piece.coordinates, self.path) {
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
    guard array.read_region(piece.origin, piece.extent) is Some(piece_values) else {
      return None
    }
    if !@chunk.copy_region_spans(
        piece.origin,
        piece.extent,
        origin,
        extent,
        piece.origin,
        piece.extent,
        fn(source, destination, count, _stride) {
          for i in 0..<count {
            result[destination + i] = piece_values[source + i]
          }
        },
      ) {
      return None
    }
  }
  Some(result)
}

///|
/// Cross-chunk writes are not atomic.
pub async fn FileU16Array::write_region(
  self : FileU16Array,
  origin : Array[Int],
  extent : Array[Int],
  values : Array[UInt16],
) -> Bool {
  guard @chunk.region_len(self.metadata, origin, extent) is Some(length) else {
    return false
  }
  if values.length() != length {
    return false
  }
  if !self.store.limits.allows_region(self.metadata, origin, extent) {
    return false
  }
  guard @chunk.region_chunks(
      self.metadata,
      origin,
      extent,
      max_chunks=self.store.limits.max_chunks(),
    )
    is Some(pieces) else {
    return false
  }
  for piece in pieces {
    let scratch = self.store.scratch()
    guard @array.open_u16_bits_from_metadata(scratch, self.metadata, self.path)
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
    let piece_values : Array[UInt16] = []
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
