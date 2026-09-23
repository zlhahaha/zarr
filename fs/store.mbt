///|
/// A persistent Zarr key/value store rooted at a local directory.
/// File-system operations are asynchronous and currently native-only.
pub struct FileStore {
  root : String
}

///|
pub fn FileStore::new(root : String) -> FileStore? {
  if root == "" {
    None
  } else {
    Some({ root, })
  }
}

///|
fn FileStore::path(self : FileStore, key : String) -> String? {
  if key == "" || key.has_prefix("/") || key.contains("\\") {
    return None
  }
  for part in key.split("/") {
    let segment = "\{part}"
    if segment == "" || segment == "." || segment == ".." {
      return None
    }
  }
  if self.root.has_suffix("/") {
    Some("\{self.root}\{key}")
  } else {
    Some("\{self.root}/\{key}")
  }
}

///|
/// Return None only when the key is absent or invalid. Other I/O errors
/// propagate to the caller.
pub async fn FileStore::get(self : FileStore, key : String) -> Bytes? {
  guard self.path(key) is Some(path) else { return None }
  if !@async_fs.exists(path) {
    return None
  }
  Some(@async_fs.read_file(path).binary())
}

///|
/// Write a key and create parent directories as needed.
pub async fn FileStore::put(
  self : FileStore,
  key : String,
  value : Bytes,
) -> Bool {
  guard self.path(key) is Some(path) else { return false }
  let parent = match key.rev_split_once("/") {
    Some((head, _)) => {
      guard self.path("\{head}") is Some(parent) else { return false }
      parent
    }
    None => self.root
  }
  if !@async_fs.exists(parent) {
    @async_fs.mkdir(parent, recursive=true)
  }
  @async_fs.write_file(
    path,
    value as &@io.Data,
    create_mode=@async_fs.CreateOrTruncate,
  )
  true
}

///|
pub async fn FileStore::put_array_metadata(
  self : FileStore,
  format : @zarr.Format,
  path : String,
  raw : String,
) -> Bool {
  guard @zarr.parse_array_metadata(raw) is Some(metadata) else { return false }
  if metadata.format != format {
    return false
  }
  guard @zarr.array_metadata_key(format, path) is Some(key) else {
    return false
  }
  guard @zarr.group_metadata_key(format, path) is Some(group_key) else {
    return false
  }
  if format == @zarr.V2 && self.get(group_key) is Some(_) {
    return false
  }
  if format == @zarr.V3 && self.get(key) is Some(bytes) {
    let previous = @utf8.decode(bytes[:]) catch { _ => return false }
    if @zarr.parse_group_metadata(previous) is Some(_) {
      return false
    }
  }
  self.put(key, @utf8.encode(raw))
}

///|
pub async fn FileStore::open_array(
  self : FileStore,
  path : String,
) -> @zarr.ArrayMetadata? {
  guard @zarr.array_metadata_key(@zarr.V2, path) is Some(v2_key) else {
    return None
  }
  guard @zarr.array_metadata_key(@zarr.V3, path) is Some(v3_key) else {
    return None
  }
  let v2 = self.get(v2_key)
  let v3 = self.get(v3_key)
  let (format, bytes) = match (v2, v3) {
    (Some(bytes), None) => (@zarr.V2, bytes)
    (None, Some(bytes)) => (@zarr.V3, bytes)
    _ => return None
  }
  let raw = @utf8.decode(bytes[:]) catch { _ => return None }
  guard @zarr.parse_array_metadata(raw) is Some(metadata) else { return None }
  if metadata.format == format {
    Some(metadata)
  } else {
    None
  }
}

///|
pub async fn FileStore::get_chunk(
  self : FileStore,
  metadata : @zarr.ArrayMetadata,
  coordinates : Array[Int],
  path : String,
) -> Bytes? {
  guard @zarr.chunk_key(metadata, coordinates, path) is Some(key) else {
    return None
  }
  self.get(key)
}

///|
pub async fn FileStore::put_chunk(
  self : FileStore,
  metadata : @zarr.ArrayMetadata,
  coordinates : Array[Int],
  path : String,
  encoded : Bytes,
) -> Bool {
  guard @zarr.chunk_key(metadata, coordinates, path) is Some(key) else {
    return false
  }
  self.put(key, encoded)
}
