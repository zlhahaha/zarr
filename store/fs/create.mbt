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
  compression? : @codec.Compression = @codec.Raw,
) -> FileU8Array? {
  if self.node_exists(path) {
    return None
  }
  guard @array.u8_metadata_json(format, shape, chunk_shape, fill, compression~)
    is Some(raw) else {
    return None
  }
  if !self.put_array_metadata(format, path, raw) {
    return None
  }
  self.open_u8(path)
}

///|
pub async fn FileStore::create_i8(
  self : FileStore,
  format : @metadata.Format,
  path : String,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Int,
  compression? : @codec.Compression = @codec.Raw,
) -> FileI8Array? {
  if self.node_exists(path) {
    return None
  }
  guard @array.i8_metadata_json(format, shape, chunk_shape, fill, compression~)
    is Some(raw) else {
    return None
  }
  if !self.put_array_metadata(format, path, raw) {
    return None
  }
  self.open_i8(path)
}

///|
pub async fn FileStore::create_bool(
  self : FileStore,
  format : @metadata.Format,
  path : String,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Bool,
  compression? : @codec.Compression = @codec.Raw,
) -> FileBoolArray? {
  if self.node_exists(path) {
    return None
  }
  guard @array.bool_metadata_json(
      format,
      shape,
      chunk_shape,
      fill,
      compression~,
    )
    is Some(raw) else {
    return None
  }
  if !self.put_array_metadata(format, path, raw) {
    return None
  }
  self.open_bool(path)
}

///|
pub async fn FileStore::create_u16(
  self : FileStore,
  format : @metadata.Format,
  path : String,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : UInt16,
  big_endian? : Bool = false,
  compression? : @codec.Compression = @codec.Raw,
) -> FileU16Array? {
  if self.node_exists(path) {
    return None
  }
  guard @array.u16_metadata_json(
      format,
      shape,
      chunk_shape,
      fill,
      big_endian~,
      compression~,
    )
    is Some(raw) else {
    return None
  }
  if !self.put_array_metadata(format, path, raw) {
    return None
  }
  self.open_u16(path)
}

///|
pub async fn FileStore::create_i16(
  self : FileStore,
  format : @metadata.Format,
  path : String,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Int16,
  big_endian? : Bool = false,
  compression? : @codec.Compression = @codec.Raw,
) -> FileI16Array? {
  if self.node_exists(path) {
    return None
  }
  guard @array.i16_metadata_json(
      format,
      shape,
      chunk_shape,
      fill,
      big_endian~,
      compression~,
    )
    is Some(raw) else {
    return None
  }
  if !self.put_array_metadata(format, path, raw) {
    return None
  }
  self.open_i16(path)
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
  compression? : @codec.Compression = @codec.Raw,
) -> FileF64Array? {
  if self.node_exists(path) {
    return None
  }
  guard @array.f64_metadata_json(
      format,
      shape,
      chunk_shape,
      fill,
      big_endian~,
      compression~,
    )
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
  compression? : @codec.Compression = @codec.Raw,
) -> FileF32Array? {
  if self.node_exists(path) {
    return None
  }
  guard @array.f32_metadata_json(
      format,
      shape,
      chunk_shape,
      fill,
      big_endian~,
      compression~,
    )
    is Some(raw) else {
    return None
  }
  if !self.put_array_metadata(format, path, raw) {
    return None
  }
  self.open_f32(path)
}

///|
pub async fn FileStore::create_i32(
  self : FileStore,
  format : @metadata.Format,
  path : String,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Int,
  big_endian? : Bool = false,
  compression? : @codec.Compression = @codec.Raw,
) -> FileI32Array? {
  if self.node_exists(path) {
    return None
  }
  guard @array.i32_metadata_json(
      format,
      shape,
      chunk_shape,
      fill,
      big_endian~,
      compression~,
    )
    is Some(raw) else {
    return None
  }
  if !self.put_array_metadata(format, path, raw) {
    return None
  }
  self.open_i32(path)
}

///|
pub async fn FileStore::create_u32(
  self : FileStore,
  format : @metadata.Format,
  path : String,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : UInt,
  big_endian? : Bool = false,
  compression? : @codec.Compression = @codec.Raw,
) -> FileU32Array? {
  if self.node_exists(path) {
    return None
  }
  guard @array.u32_metadata_json(
      format,
      shape,
      chunk_shape,
      fill,
      big_endian~,
      compression~,
    )
    is Some(raw) else {
    return None
  }
  if !self.put_array_metadata(format, path, raw) {
    return None
  }
  self.open_u32(path)
}

///|
pub async fn FileStore::create_i64(
  self : FileStore,
  format : @metadata.Format,
  path : String,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Int64,
  big_endian? : Bool = false,
  compression? : @codec.Compression = @codec.Raw,
) -> FileI64Array? {
  if self.node_exists(path) {
    return None
  }
  guard @array.i64_metadata_json(
      format,
      shape,
      chunk_shape,
      fill,
      big_endian~,
      compression~,
    )
    is Some(raw) else {
    return None
  }
  if !self.put_array_metadata(format, path, raw) {
    return None
  }
  self.open_i64(path)
}

///|
pub async fn FileStore::create_u64(
  self : FileStore,
  format : @metadata.Format,
  path : String,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : UInt64,
  big_endian? : Bool = false,
  compression? : @codec.Compression = @codec.Raw,
) -> FileU64Array? {
  if self.node_exists(path) {
    return None
  }
  guard @array.u64_metadata_json(
      format,
      shape,
      chunk_shape,
      fill,
      big_endian~,
      compression~,
    )
    is Some(raw) else {
    return None
  }
  if !self.put_array_metadata(format, path, raw) {
    return None
  }
  self.open_u64(path)
}
