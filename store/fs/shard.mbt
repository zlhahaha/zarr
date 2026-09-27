///|
/// Read only the fixed-size index and selected inner chunk from a shard.
/// Empty bytes represent malformed shard data so typed decoders fail closed;
/// None is reserved for a missing shard or a valid absent inner chunk.
async fn FileStore::get_sharded_chunk(
  self : FileStore,
  metadata : @metadata.ArrayMetadata,
  coordinates : Array[Int],
  path : String,
) -> Bytes? {
  guard metadata.sharding is Some(layout) else { return Some(b"") }
  guard @chunk.chunk_key(metadata, coordinates, path) is Some(_) else {
    return Some(b"")
  }
  guard @shard.coordinates(metadata, coordinates) is Some((outer, within)) else {
    return Some(b"")
  }
  guard @chunk.shard_key(metadata, outer, path) is Some(key) else {
    return Some(b"")
  }
  guard self.path(key) is Some(filename) else { return Some(b"") }
  if !@async_fs.exists(filename) {
    return None
  }
  let file = @async_fs.open(filename, mode=@async_fs.ReadOnly)
  defer file.close()
  let size = file.size()
  if size < layout.index_size.to_int64() {
    return Some(b"")
  }
  let index_at = if layout.index_at_start {
    0L
  } else {
    size - layout.index_size.to_int64()
  }
  let index = file.read_exactly_at(layout.index_size, position=index_at)
  match @shard.entry(layout, index, within, size) {
    @shard.Absent => None
    @shard.Invalid => Some(b"")
    @shard.Data(at, length) => Some(file.read_exactly_at(length, position=at))
  }
}
