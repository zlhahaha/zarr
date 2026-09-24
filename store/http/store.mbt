///|
/// Read-only HTTP access to a Zarr hierarchy. Each hydration call fetches
/// only metadata and the chunks intersecting its requested rectangle.
pub struct HttpStore {
  base_url : String
  max_metadata_bytes : Int
  max_chunk_bytes : Int
  max_chunks : Int
}

///|
pub fn HttpStore::new(
  base_url : String,
  max_metadata_bytes? : Int = 1048576,
  max_chunk_bytes? : Int = 67108864,
  max_chunks? : Int = 1024,
) -> HttpStore? {
  if !(base_url.has_prefix("http://") || base_url.has_prefix("https://")) ||
    base_url.contains("?") ||
    base_url.contains("#") ||
    max_metadata_bytes <= 0 ||
    max_chunk_bytes <= 0 ||
    max_chunks <= 0 {
    return None
  }
  Some({ base_url, max_metadata_bytes, max_chunk_bytes, max_chunks, })
}

///|
priv enum FetchResult {
  Found(Bytes)
  Missing
  Failed
}

///|
fn hex_digit(nibble : Int) -> Char {
  (if nibble < 10 { 48 + nibble } else { 55 + nibble }).unsafe_to_char()
}

///|
/// Preserve separators while escaping every non-unreserved UTF-8 byte.
fn encode_key(key : String) -> String? {
  guard @chunk.normalized_path(key, @metadata.V2) is Some(normalized) else {
    return None
  }
  if key == "" || key != normalized {
    return None
  }
  let result = StringBuilder()
  for byte in @utf8.encode(key) {
    let value = byte.to_int()
    if (value >= 65 && value <= 90) ||
      (value >= 97 && value <= 122) ||
      (value >= 48 && value <= 57) ||
      value == 45 ||
      value == 95 ||
      value == 46 ||
      value == 126 ||
      value == 47 {
      result.write_char(value.unsafe_to_char())
    } else {
      result.write_char('%')
      result.write_char(hex_digit(value >> 4))
      result.write_char(hex_digit(value & 15))
    }
  }
  Some(result.to_string())
}

///|
async fn HttpStore::fetch(
  self : HttpStore,
  key : String,
  limit : Int,
) -> FetchResult {
  guard encode_key(key) is Some(encoded) else { return Failed }
  let url = if self.base_url.has_suffix("/") {
    "\{self.base_url}\{encoded}"
  } else {
    "\{self.base_url}/\{encoded}"
  }
  let (response, client) = @client_http.get_stream(url) catch {
    _ => return Failed
  }
  defer client.close()
  match response.code {
    404 => Missing
    200 => {
      let output : Array[Byte] = []
      for ;; {
        let next = client.read_some(max_len=32768) catch { _ => return Failed }
        match next {
          None => return Found(Bytes::from_array(output))
          Some(bytes) => {
            if bytes.length() > limit - output.length() {
              return Failed
            }
            output.append(bytes.to_array()[:])
          }
        }
      }
      Failed
    }
    _ => Failed
  }
}

///|
/// Download the array metadata and only chunks touched by a bounded region.
/// The returned MemoryStore can be opened with typed functions in `array/`.
/// Missing chunks retain their declared fill value; HTTP failures do not.
pub async fn HttpStore::hydrate_region(
  self : HttpStore,
  path : String,
  origin : Array[Int],
  extent : Array[Int],
) -> @store.MemoryStore? {
  guard @chunk.array_metadata_key(@metadata.V2, path) is Some(v2_key) else {
    return None
  }
  guard @chunk.array_metadata_key(@metadata.V3, path) is Some(v3_key) else {
    return None
  }
  let v2 = self.fetch(v2_key, self.max_metadata_bytes)
  let v3 = self.fetch(v3_key, self.max_metadata_bytes)
  let (format, bytes) = match (v2, v3) {
    (Found(bytes), Missing) => (@metadata.V2, bytes)
    (Missing, Found(bytes)) => (@metadata.V3, bytes)
    _ => return None
  }
  if format == @metadata.V2 {
    guard @chunk.group_metadata_key(format, path) is Some(group_key) else {
      return None
    }
    match self.fetch(group_key, self.max_metadata_bytes) {
      Missing => ()
      _ => return None
    }
  }
  let raw = @utf8.decode(bytes[:]) catch { _ => return None }
  guard @metadata.parse_array_metadata(raw) is Some(metadata) else {
    return None
  }
  if metadata.format != format {
    return None
  }
  guard @chunk.region_len(metadata, origin, extent) is Some(length) else {
    return None
  }
  let scratch = @store.MemoryStore::new()
  if !scratch.put_array_metadata(format, path, raw) {
    return None
  }
  if length == 0 {
    return Some(scratch)
  }
  let mut count = 1
  for i in 0..<origin.length() {
    let side = metadata.chunk_shape[i]
    if side <= 0 {
      return None
    }
    let first = origin[i] / side
    let last = (origin[i] + extent[i] - 1) / side
    let span = last - first + 1
    if count > self.max_chunks / span {
      return None
    }
    count *= span
  }
  guard @chunk.region_chunks(metadata, origin, extent) is Some(pieces) else {
    return None
  }
  for piece in pieces {
    guard @chunk.chunk_key(metadata, piece.coordinates, path) is Some(key) else {
      return None
    }
    match self.fetch(key, self.max_chunk_bytes) {
      Found(chunk) =>
        if !scratch.put_chunk(metadata, piece.coordinates, path, chunk) {
          return None
        }
      Missing => ()
      Failed => return None
    }
  }
  Some(scratch)
}
