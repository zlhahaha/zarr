///|
/// A persistent Zarr key/value store rooted at a local directory.
/// File-system operations are asynchronous and currently native-only.
pub struct FileStore {
  root : String
  consolidated : Map[String, Json]?
  v3_consolidated : Map[String, Json]?
  v3_root : Json?
  read_only : Bool
}

///|
pub fn FileStore::new(root : String) -> FileStore? {
  if root == "" {
    None
  } else {
    Some({
      root,
      consolidated: None,
      v3_consolidated: None,
      v3_root: None,
      read_only: false,
    })
  }
}

///|
/// Open a read-only Zarr v2 consolidated metadata snapshot. Chunk bytes still
/// come from the filesystem; metadata comes only from `.zmetadata`.
pub async fn FileStore::open_consolidated(root : String) -> FileStore? {
  guard FileStore::new(root) is Some(plain) else { return None }
  guard plain.get(".zmetadata") is Some(bytes) else { return None }
  let raw = @utf8.decode(bytes[:]) catch { _ => return None }
  guard @json.parse(raw) is Object(document) else { return None }
  guard document.get("zarr_consolidated_format") is Some(Number(version, ..)) else {
    return None
  }
  if version != 1.0 {
    return None
  }
  guard document.get("metadata") is Some(Object(entries)) else { return None }
  Some({
    root,
    consolidated: Some(entries),
    v3_consolidated: None,
    v3_root: None,
    read_only: true,
  })
}

///|
/// Open a read-only snapshot of the v3 inline consolidated-metadata
/// convention. Metadata comes only from the root index; chunks remain on disk.
pub async fn FileStore::open_consolidated_v3(root : String) -> FileStore? {
  guard FileStore::new(root) is Some(plain) else { return None }
  guard plain.get("zarr.json") is Some(bytes) else { return None }
  let raw = @utf8.decode(bytes[:]) catch { _ => return None }
  guard @metadata.parse_group_metadata(raw) is Some(group) else { return None }
  if group.format != @metadata.V3 {
    return None
  }
  guard @json.parse(raw) is Object(document) else { return None }
  guard document.get("consolidated_metadata") is Some(Object(index)) else {
    return None
  }
  if index.get("kind") != Some(Json::string("inline")) ||
    index.get("must_understand") != Some(Json::boolean(false)) {
    return None
  }
  guard index.get("metadata") is Some(Object(entries)) else { return None }
  for path, value in entries {
    if path == "" || @chunk.array_metadata_key(@metadata.V3, path) is None {
      return None
    }
    let entry = value.stringify()
    if @metadata.parse_array_metadata(entry) is Some(array) {
      if array.format != @metadata.V3 {
        return None
      }
    } else if @metadata.parse_group_metadata(entry) is Some(child) {
      if child.format != @metadata.V3 {
        return None
      }
    } else {
      return None
    }
  }
  Some({
    root,
    consolidated: None,
    v3_consolidated: Some(entries),
    v3_root: Some(Json::object(document)),
    read_only: true,
  })
}

///|
fn v2_metadata_key(key : String) -> Bool {
  key == ".zarray" ||
  key == ".zgroup" ||
  key == ".zattrs" ||
  key.has_suffix("/.zarray") ||
  key.has_suffix("/.zgroup") ||
  key.has_suffix("/.zattrs")
}

///|
fn reserved_windows_name(segment : String) -> Bool {
  let name = match segment.split_once(".") {
    Some((base, _)) => "\{base}".to_upper()
    None => segment.to_upper()
  }
  match name {
    "CON"
    | "PRN"
    | "AUX"
    | "NUL"
    | "COM1"
    | "COM2"
    | "COM3"
    | "COM4"
    | "COM5"
    | "COM6"
    | "COM7"
    | "COM8"
    | "COM9"
    | "LPT1"
    | "LPT2"
    | "LPT3"
    | "LPT4"
    | "LPT5"
    | "LPT6"
    | "LPT7"
    | "LPT8"
    | "LPT9" => true
    _ => false
  }
}

///|
fn FileStore::path(self : FileStore, key : String) -> String? {
  if key == "" || key.has_prefix("/") || key.contains("\\") {
    return None
  }
  for part in key.split("/") {
    let segment = "\{part}"
    if segment == "" ||
      segment == "." ||
      segment == ".." ||
      segment.has_suffix(".") ||
      segment.has_suffix(" ") ||
      reserved_windows_name(segment) ||
      segment.contains(":") ||
      segment.contains("<") ||
      segment.contains(">") ||
      segment.contains("\"") ||
      segment.contains("|") ||
      segment.contains("?") ||
      segment.contains("*") {
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
  if self.v3_consolidated is Some(entries) {
    if key == "zarr.json" {
      guard self.v3_root is Some(root) else { return None }
      return Some(@utf8.encode(root.stringify()))
    }
    if key.has_suffix("/zarr.json") {
      guard key.rev_split_once("/") is Some((logical, _)) else { return None }
      guard entries.get("\{logical}") is Some(entry) else { return None }
      return Some(@utf8.encode(entry.stringify()))
    }
    if v2_metadata_key(key) || key == ".zmetadata" {
      return None
    }
  }
  if self.consolidated is Some(entries) {
    if v2_metadata_key(key) {
      guard entries.get(key) is Some(Object(fields)) else { return None }
      return Some(@utf8.encode(Json::object(fields).stringify()))
    }
    if key == "zarr.json" || key.has_suffix("/zarr.json") {
      return None
    }
  }
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
  if self.read_only {
    return false
  }
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
  format : @metadata.Format,
  path : String,
  raw : String,
) -> Bool {
  guard @metadata.parse_array_metadata(raw) is Some(metadata) else {
    return false
  }
  if metadata.format != format {
    return false
  }
  guard @chunk.array_metadata_key(format, path) is Some(key) else {
    return false
  }
  guard @chunk.group_metadata_key(format, path) is Some(group_key) else {
    return false
  }
  let other = if format == @metadata.V2 { @metadata.V3 } else { @metadata.V2 }
  let other_array = match @chunk.array_metadata_key(other, path) {
    Some(key) => self.get(key) is Some(_)
    None => false
  }
  let other_group = match @chunk.group_metadata_key(other, path) {
    Some(key) => self.get(key) is Some(_)
    None => false
  }
  if other_array || other_group {
    return false
  }
  if format == @metadata.V2 && self.get(group_key) is Some(_) {
    return false
  }
  if format == @metadata.V3 && self.get(key) is Some(bytes) {
    let previous = @utf8.decode(bytes[:]) catch { _ => return false }
    if @metadata.parse_group_metadata(previous) is Some(_) {
      return false
    }
  }
  self.put(key, @utf8.encode(raw))
}

///|
pub async fn FileStore::open_array(
  self : FileStore,
  path : String,
) -> @metadata.ArrayMetadata? {
  guard @chunk.array_metadata_key(@metadata.V2, path) is Some(v2_key) else {
    return None
  }
  let v3_key = @chunk.array_metadata_key(@metadata.V3, path)
  guard @chunk.group_metadata_key(@metadata.V2, path) is Some(v2_group_key) else {
    return None
  }
  if self.get(v2_group_key) is Some(_) {
    return None
  }
  let v2 = self.get(v2_key)
  let v3 = match v3_key {
    Some(key) => self.get(key)
    None => None
  }
  let (format, bytes) = match (v2, v3) {
    (Some(bytes), None) => (@metadata.V2, bytes)
    (None, Some(bytes)) => (@metadata.V3, bytes)
    _ => return None
  }
  let raw = @utf8.decode(bytes[:]) catch { _ => return None }
  guard @metadata.parse_array_metadata(raw) is Some(metadata) else {
    return None
  }
  if metadata.format == format {
    Some(metadata)
  } else {
    None
  }
}

///|
pub async fn FileStore::get_chunk(
  self : FileStore,
  metadata : @metadata.ArrayMetadata,
  coordinates : Array[Int],
  path : String,
) -> Bytes? {
  guard @chunk.chunk_key(metadata, coordinates, path) is Some(key) else {
    return None
  }
  self.get(key)
}

///|
pub async fn FileStore::put_chunk(
  self : FileStore,
  metadata : @metadata.ArrayMetadata,
  coordinates : Array[Int],
  path : String,
  encoded : Bytes,
) -> Bool {
  guard @chunk.chunk_key(metadata, coordinates, path) is Some(key) else {
    return false
  }
  self.put(key, encoded)
}
