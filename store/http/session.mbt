///|
/// An explicitly pinned metadata view, not an object-data snapshot.
/// No metadata probes are repeated by hydrate_region_result.
pub struct ArraySession {
  store : HttpStore
  path : String
  raw : String
  format : @metadata.Format
  metadata : @metadata.ArrayMetadata
  scratch_raw : String
}

///|
/// Fresh sessions isolate the encoded-object cache as well as metadata, so
/// refresh cannot accidentally rediscover cached old documents or chunks.
pub async fn HttpStore::open_array_session_result(
  self : HttpStore,
  path : String,
  fresh~ : Bool = true,
) -> Result[ArraySession, @store.AccessError] {
  let transport = if fresh {
    { ..self, cache: Map([]), cache_bytes: 0, cache_entries: 0, tick: 0UL, }
  } else {
    self
  }
  let (format, raw, metadata) = match transport.load_array_result(path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let scratch_raw = if metadata.sharding is Some(_) {
    guard @shard.inner_metadata_json(raw) is Some(inner) else {
      return Err(@store.UnsupportedMetadata(path))
    }
    inner
  } else {
    raw
  }
  Ok({ store: transport, path, raw, format, metadata, scratch_raw, })
}

///|
/// A defensive copy: mutating its shape/codec containers cannot alter a session.
pub fn ArraySession::metadata(self : ArraySession) -> @metadata.ArrayMetadata {
  guard @metadata.parse_array_metadata(self.raw) is Some(parsed) else {
    abort("validated session metadata")
  }
  guard @shard.prepare(parsed) is Some(prepared) else {
    abort("validated session layout")
  }
  prepared
}

///|
pub async fn ArraySession::hydrate_region_result(
  self : ArraySession,
  origin : Array[Int32],
  extent : Array[Int32],
) -> Result[@store.MemoryStore, @store.AccessError] {
  self.store.hydrate_prepared(
    self.path,
    origin,
    extent,
    self.format,
    self.scratch_raw,
    self.metadata,
  )
}

///|
/// Return a fresh independent session. Existing sessions/readers keep their
/// pinned metadata and cache; they are not silently modified.
pub async fn ArraySession::refresh(
  self : ArraySession,
) -> Result[ArraySession, @store.AccessError] {
  self.store.open_array_session_result(self.path, fresh=true)
}
