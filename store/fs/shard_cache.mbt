///|
/// Cumulative counters for this FileStore. Bytes count explicit library range
/// reads, not physical disk I/O; OS page-cache activity is not measured.
pub(all) struct ShardReadStats {
  index_reads : Int
  index_bytes : Int64
  index_cache_hits : Int
  payload_reads : Int
  payload_bytes : Int64
  peak_cached_index_bytes : Int
} derive(Debug)

///|
pub extend ShardReadStats with Debug::{to_repr}

///|
fn empty_shard_stats() -> ShardReadStats {
  {
    index_reads: 0,
    index_bytes: 0L,
    index_cache_hits: 0,
    payload_reads: 0,
    payload_bytes: 0L,
    peak_cached_index_bytes: 0,
  }
}

///|
pub fn FileStore::shard_read_stats(self : FileStore) -> ShardReadStats {
  self.shard_metrics.val
}

///|
/// Reset counters only; no indices persist between typed region operations.
pub fn FileStore::reset_shard_read_stats(self : FileStore) -> Unit {
  self.shard_metrics.val = empty_shard_stats()
}

///|
/// Operation-local, bounded FIFO cache. Never shared by concurrent reads and
/// never retained by FileStore after a region read completes or raises.
priv struct ShardSession {
  store : FileStore
  indices : Map[String, @shard.ValidatedIndex]
  order : Array[String]
  mut bytes : Int
}

///|
fn FileStore::shard_session(self : FileStore) -> ShardSession {
  { store: self, indices: {}, order: [], bytes: 0, }
}

///|
fn ShardSession::forget(self : ShardSession, key : String) -> Unit {
  if self.indices.get(key) is Some(index) {
    self.bytes -= index.size_bytes()
    self.indices.remove(key)
    for i in 0..<self.order.length() {
      if self.order[i] == key {
        let _ = self.order.remove(i)
        break
      }
    }
  }
}

///|
fn ShardSession::cached(
  self : ShardSession,
  key : String,
  size : Int64,
) -> @shard.ValidatedIndex? {
  if self.indices.get(key) is Some(index) {
    if index.matches_size(size) {
      let stats = self.store.shard_metrics.val
      self.store.shard_metrics.val = {
        ..stats,
        index_cache_hits: stats.index_cache_hits + 1,
      }
      return Some(index)
    }
    self.forget(key)
  }
  None
}

///|
fn ShardSession::remember(
  self : ShardSession,
  key : String,
  index : @shard.ValidatedIndex,
) -> Unit {
  let limit = self.store.shard_index_cache_bytes
  let entries = self.store.shard_index_cache_entries
  let length = index.size_bytes()
  if entries == 0 || length > limit {
    return
  }
  self.forget(key)
  while self.bytes > limit - length || self.order.length() >= entries {
    self.forget(self.order[0])
  }
  self.indices[key] = index
  self.order.push(key)
  self.bytes += length
  let stats = self.store.shard_metrics.val
  if self.bytes > stats.peak_cached_index_bytes {
    self.store.shard_metrics.val = {
      ..stats,
      peak_cached_index_bytes: self.bytes,
    }
  }
}

///|
async fn ShardSession::get_chunk(
  self : ShardSession,
  metadata : @metadata.ArrayMetadata,
  coordinates : Array[Int],
  path : String,
) -> Bytes? {
  if metadata.sharding is Some(_) {
    self.get_sharded_chunk(metadata, coordinates, path)
  } else {
    self.store.get_chunk(metadata, coordinates, path)
  }
}
