///|
async fn FileStore::node_exists(self : FileStore, path : String) -> Bool {
  for format in [@metadata.V2, @metadata.V3] {
    if @chunk.array_metadata_key(format, path) is Some(key) &&
      self.get(key) is Some(_) {
      return true
    }
    if @chunk.group_metadata_key(format, path) is Some(key) &&
      self.get(key) is Some(_) {
      return true
    }
  }
  false
}

///|
pub async fn FileStore::create_u8(
  self : FileStore,
  format : @metadata.Format,
  path : String,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Byte,
) -> FileU8Array? {
  if self.node_exists(path) {
    return None
  }
  guard @array.u8_metadata_json(format, shape, chunk_shape, fill) is Some(raw) else {
    return None
  }
  if !self.put_array_metadata(format, path, raw) {
    return None
  }
  self.open_u8(path)
}

///|
pub async fn FileStore::create_f64(
  self : FileStore,
  format : @metadata.Format,
  path : String,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Double,
  big_endian? : Bool = false,
) -> FileF64Array? {
  if self.node_exists(path) {
    return None
  }
  guard @array.f64_metadata_json(format, shape, chunk_shape, fill, big_endian~)
    is Some(raw) else {
    return None
  }
  if !self.put_array_metadata(format, path, raw) {
    return None
  }
  self.open_f64(path)
}

///|
pub async fn FileStore::create_f32(
  self : FileStore,
  format : @metadata.Format,
  path : String,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Float,
  big_endian? : Bool = false,
) -> FileF32Array? {
  if self.node_exists(path) {
    return None
  }
  guard @array.f32_metadata_json(format, shape, chunk_shape, fill, big_endian~)
    is Some(raw) else {
    return None
  }
  if !self.put_array_metadata(format, path, raw) {
    return None
  }
  self.open_f32(path)
}
