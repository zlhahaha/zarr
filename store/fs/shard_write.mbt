///|
/// Complete-shard writes avoid reading or merging the previous shard. Commit
/// uses the same staged sibling + replacement rename as FileStore::put.
async fn FileStore::write_typed_shard(
  self : FileStore,
  metadata : @metadata.ArrayMetadata,
  path : String,
  coordinates : Array[Int32],
  value_count : Int32,
  write : (
    @store.MemoryStore,
    @metadata.ArrayMetadata,
    Array[Int32],
    Array[Int32],
  ) -> Bool,
) -> Bool {
  if self.read_only {
    return false
  }
  guard metadata.sharding is Some(layout) else { return false }
  guard @chunk.shard_key(metadata, coordinates, path) is Some(key) else {
    return false
  }
  let origin = Array::makei(coordinates.length(), i => {
    coordinates[i] * layout.shard_shape[i]
  })
  let extent = Array::makei(coordinates.length(), i => {
    let remaining = metadata.shape[i] - origin[i]
    if remaining < layout.shard_shape[i] {
      remaining
    } else {
      layout.shard_shape[i]
    }
  })
  guard @chunk.region_len(metadata, origin, extent) is Some(length) else {
    return false
  }
  if length != value_count ||
    !self.limits.allows_region(metadata, origin, extent) ||
    layout.index_size > self.limits.max_chunk_bytes() {
    return false
  }
  guard @chunk.region_chunks(
      metadata,
      origin,
      extent,
      max_chunks=self.limits.max_chunks(),
    )
    is Some(pieces) else {
    return false
  }
  let ordinary = { ..metadata, sharding: None, }
  let scratch = self.scratch()
  if !write(scratch, ordinary, origin, extent) {
    return false
  }
  let count = (layout.index_size - (if layout.index_crc32c { 4 } else { 0 })) /
    16
  let chunks : Array[Bytes?] = Array::make(count, None)
  let mut encoded_size = layout.index_size
  for piece in pieces {
    guard scratch.get_chunk(ordinary, piece.coordinates, path) is Some(bytes) else {
      return false
    }
    if bytes.length() > self.limits.max_chunk_bytes() - encoded_size {
      return false
    }
    encoded_size += bytes.length()
    let mut at = 0
    for i in 0..<coordinates.length() {
      at = at * layout.chunks_per_shard[i] +
        piece.coordinates[i] -
        coordinates[i] * layout.chunks_per_shard[i]
    }
    chunks[at] = Some(bytes)
  }
  guard @shard.encode(layout, chunks, max_bytes=self.limits.max_chunk_bytes())
    is Some(bytes) else {
    return false
  }
  self.put(key, bytes)
}

///|
/// Values cover exactly the clipped logical shard rectangle, in C order.
pub async fn FileU8Array::write_shard(
  self : FileU8Array,
  coordinates : Array[Int32],
  values : Bytes,
) -> Bool {
  self.store.write_typed_shard(
    self.metadata,
    self.path,
    coordinates,
    values.length(),
    (scratch, metadata, origin, extent) => {
      guard @array.open_u8_from_metadata(scratch, metadata, self.path)
        is Some(array) else {
        return false
      }
      array.write_region(origin, extent, values)
    },
  )
}

///|
pub async fn FileU16Array::write_shard(
  self : FileU16Array,
  coordinates : Array[Int32],
  values : Array[UInt16],
) -> Bool {
  self.store.write_typed_shard(
    self.metadata,
    self.path,
    coordinates,
    values.length(),
    (scratch, metadata, origin, extent) => {
      guard @array.open_u16_from_metadata(scratch, metadata, self.path)
        is Some(array) else {
        return false
      }
      array.write_region(origin, extent, values)
    },
  )
}

///|
pub async fn FileF32Array::write_shard(
  self : FileF32Array,
  coordinates : Array[Int32],
  values : Array[Float],
) -> Bool {
  self.store.write_typed_shard(
    self.metadata,
    self.path,
    coordinates,
    values.length(),
    (scratch, metadata, origin, extent) => {
      guard @array.open_f32_from_metadata(scratch, metadata, self.path)
        is Some(array) else {
        return false
      }
      array.write_region(origin, extent, values)
    },
  )
}

///|
async fn FileStore::create_sharded_document(
  self : FileStore,
  path : String,
  inner : String?,
  shard_shape : Array[Int32],
  at_start : Bool,
  big_endian : Bool,
  checksum : Bool,
) -> Bool {
  if self.read_only || self.node_exists(path) {
    return false
  }
  guard inner is Some(inner) else { return false }
  guard @shard.metadata_json(
      inner,
      shard_shape,
      index_at_start=at_start,
      index_big_endian=big_endian,
      index_crc32c=checksum,
    )
    is Some(raw) else {
    return false
  }
  guard @metadata.parse_array_metadata(raw) is Some(outer) else { return false }
  guard @shard.prepare(outer) is Some(metadata) else { return false }
  if !self.limits.allows_metadata(@utf8.encode(raw)) ||
    !self.limits.allows_array(metadata) {
    return false
  }
  guard metadata.sharding is Some(layout) else { return false }
  if layout.index_size > self.limits.max_chunk_bytes() {
    return false
  }
  self.put_array_metadata(@metadata.V3, path, raw)
}

///|
pub async fn FileStore::create_sharded_u8(
  self : FileStore,
  path : String,
  shape : Array[Int32],
  chunk_shape : Array[Int32],
  shard_shape : Array[Int32],
  fill : Byte,
  compression~ : @codec.Compression = @codec.Raw,
  index_at_start~ : Bool = false,
  index_big_endian~ : Bool = false,
  index_crc32c~ : Bool = true,
) -> FileU8Array? {
  if !self.create_sharded_document(
      path,
      @array.u8_metadata_json(
        @metadata.V3,
        shape,
        chunk_shape,
        fill,
        compression~,
      ),
      shard_shape,
      index_at_start,
      index_big_endian,
      index_crc32c,
    ) {
    return None
  }
  self.open_u8(path)
}

///|
pub async fn FileStore::create_sharded_u16(
  self : FileStore,
  path : String,
  shape : Array[Int32],
  chunk_shape : Array[Int32],
  shard_shape : Array[Int32],
  fill : UInt16,
  compression~ : @codec.Compression = @codec.Raw,
  big_endian~ : Bool = false,
  index_at_start~ : Bool = false,
  index_big_endian~ : Bool = false,
  index_crc32c~ : Bool = true,
) -> FileU16Array? {
  if !self.create_sharded_document(
      path,
      @array.u16_metadata_json(
        @metadata.V3,
        shape,
        chunk_shape,
        fill,
        compression~,
        big_endian~,
      ),
      shard_shape,
      index_at_start,
      index_big_endian,
      index_crc32c,
    ) {
    return None
  }
  self.open_u16(path)
}

///|
pub async fn FileStore::create_sharded_f32(
  self : FileStore,
  path : String,
  shape : Array[Int32],
  chunk_shape : Array[Int32],
  shard_shape : Array[Int32],
  fill : Float,
  compression~ : @codec.Compression = @codec.Raw,
  big_endian~ : Bool = false,
  index_at_start~ : Bool = false,
  index_big_endian~ : Bool = false,
  index_crc32c~ : Bool = true,
) -> FileF32Array? {
  if !self.create_sharded_document(
      path,
      @array.f32_metadata_json(
        @metadata.V3,
        shape,
        chunk_shape,
        fill,
        compression~,
        big_endian~,
      ),
      shard_shape,
      index_at_start,
      index_big_endian,
      index_crc32c,
    ) {
    return None
  }
  self.open_f32(path)
}
