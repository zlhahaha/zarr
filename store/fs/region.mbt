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
  let result = Bytes::make(length, b'\x00').to_array()
  for linear in 0..<length {
    guard self.read(@chunk.region_coords(origin, extent, linear)) is Some(value) else {
      return None
    }
    result[linear] = value
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
  for linear in 0..<length {
    if !self.write(@chunk.region_coords(origin, extent, linear), values[linear]) {
      return false
    }
  }
  true
}

///|
pub async fn FileF32Array::read_region(
  self : FileF32Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[Float]? {
  guard @chunk.region_len(self.metadata, origin, extent) is Some(length) else {
    return None
  }
  let result : Array[Float] = []
  for linear in 0..<length {
    guard self.read(@chunk.region_coords(origin, extent, linear)) is Some(value) else {
      return None
    }
    result.push(value)
  }
  Some(result)
}

///|
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
  for linear in 0..<length {
    if !self.write(@chunk.region_coords(origin, extent, linear), values[linear]) {
      return false
    }
  }
  true
}

///|
pub async fn FileF64Array::read_region(
  self : FileF64Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[Double]? {
  guard @chunk.region_len(self.metadata, origin, extent) is Some(length) else {
    return None
  }
  let result : Array[Double] = []
  for linear in 0..<length {
    guard self.read(@chunk.region_coords(origin, extent, linear)) is Some(value) else {
      return None
    }
    result.push(value)
  }
  Some(result)
}

///|
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
  for linear in 0..<length {
    if !self.write(@chunk.region_coords(origin, extent, linear), values[linear]) {
      return false
    }
  }
  true
}

///|
pub async fn FileI32Array::read_region(
  self : FileI32Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[Int]? {
  guard @chunk.region_len(self.metadata, origin, extent) is Some(length) else {
    return None
  }
  let result : Array[Int] = []
  for linear in 0..<length {
    guard self.read(@chunk.region_coords(origin, extent, linear)) is Some(value) else {
      return None
    }
    result.push(value)
  }
  Some(result)
}

///|
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
  for linear in 0..<length {
    if !self.write(@chunk.region_coords(origin, extent, linear), values[linear]) {
      return false
    }
  }
  true
}
