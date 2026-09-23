///|
/// In-memory byte-key store for examples, tests, and embedding. The Zarr
/// storage format itself is independent of the storage medium.
pub struct MemoryStore {
  entries : Map[String, Bytes]
}

///|
pub fn MemoryStore::new() -> MemoryStore {
  { entries: Map([]) }
}

///|
pub fn MemoryStore::get(self : MemoryStore, key : String) -> Bytes? {
  self.entries.get(key)
}

///|
pub fn MemoryStore::put(
  self : MemoryStore,
  key : String,
  value : Bytes,
) -> Unit {
  self.entries.set(key, value)
}

///|
pub fn MemoryStore::delete(self : MemoryStore, key : String) -> Unit {
  self.entries.remove(key)
}

///|
/// Store already-valid v2/v3 array metadata under its prescribed key.
pub fn MemoryStore::put_array_metadata(
  self : MemoryStore,
  format : Format,
  path : String,
  raw : String,
) -> Bool {
  guard parse_array_metadata(raw) is Some(parsed) else { return false }
  if parsed.format != format {
    return false
  }
  guard array_metadata_key(format, path) is Some(key) else { return false }
  self.put(key, @utf8.encode(raw))
  true
}

///|
/// Open metadata at a path. A mixed v2/v3 path is ambiguous and rejected.
pub fn MemoryStore::open_array(
  self : MemoryStore,
  path : String,
) -> ArrayMetadata? {
  guard array_metadata_key(V2, path) is Some(v2_key) else { return None }
  guard array_metadata_key(V3, path) is Some(v3_key) else { return None }
  let v2 = self.get(v2_key)
  let v3 = self.get(v3_key)
  let (expected, bytes) = match (v2, v3) {
    (Some(bytes), None) => (V2, bytes)
    (None, Some(bytes)) => (V3, bytes)
    _ => return None
  }
  let raw = @utf8.decode(bytes[:]) catch { _ => return None }
  guard parse_array_metadata(raw) is Some(parsed) else { return None }
  if parsed.format == expected {
    Some(parsed)
  } else {
    None
  }
}

///|
/// Store an already-encoded chunk. Codecs are not applied here.
pub fn MemoryStore::put_chunk(
  self : MemoryStore,
  metadata : ArrayMetadata,
  coordinates : Array[Int],
  path : String,
  encoded : Bytes,
) -> Bool {
  guard chunk_key(metadata, coordinates, path) is Some(key) else {
    return false
  }
  self.put(key, encoded)
  true
}

///|
/// Retrieve encoded chunk bytes. The caller must decode metadata codecs.
pub fn MemoryStore::get_chunk(
  self : MemoryStore,
  metadata : ArrayMetadata,
  coordinates : Array[Int],
  path : String,
) -> Bytes? {
  guard chunk_key(metadata, coordinates, path) is Some(key) else { return None }
  self.get(key)
}
