///|
/// Read only the fixed-size index and selected inner chunk from a shard.
/// Empty bytes represent malformed shard data so typed decoders fail closed;
/// None is reserved for a missing shard or a valid absent inner chunk.
async fn ShardSession::get_sharded_chunk(
  self : ShardSession,
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
  guard self.store.path(key) is Some(filename) else { return Some(b"") }
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
  let index = match self.cached(filename, size) {
    Some(index) => index
    None => {
      let bytes = file.read_exactly_at(layout.index_size, position=index_at)
      let stats = self.store.shard_metrics.val
      self.store.shard_metrics.val = {
        ..stats,
        index_reads: stats.index_reads + 1,
        index_bytes: stats.index_bytes + layout.index_size.to_int64(),
      }
      guard @shard.validate_index(layout, bytes, size) is Some(index) else {
        return Some(b"")
      }
      self.remember(filename, index)
      index
    }
  }
  match index.entry(within) {
    @shard.Absent => None
    @shard.Invalid => Some(b"")
    @shard.Data(at, length) => {
      let bytes = file.read_exactly_at(length, position=at)
      let stats = self.store.shard_metrics.val
      self.store.shard_metrics.val = {
        ..stats,
        payload_reads: stats.payload_reads + 1,
        payload_bytes: stats.payload_bytes + length.to_int64(),
      }
      Some(bytes)
    }
  }
}
