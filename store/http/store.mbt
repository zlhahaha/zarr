///|
/// Read-only HTTP access to a Zarr hierarchy. Each hydration call fetches
/// only metadata and the chunks intersecting its requested rectangle.
pub struct HttpStore {
  base_url : String
  max_metadata_bytes : Int32
  max_chunk_bytes : Int32
  max_chunks : Int32
  max_cache_bytes : Int32
  max_cache_entries : Int32
  cache : Map[String, CacheEntry]
  mut cache_bytes : Int32
  mut cache_entries : Int32
  mut tick : UInt64
  limits : @store.ReadLimits
  max_hydration_bytes : Int32
  request_timeout_ms : Int32
  get_headers : ((String, String?, String?) -> Map[String, String]?)?
}

///|
pub struct CacheEntry {
  bytes : Bytes
  access : UInt64
}

///|
pub fn HttpStore::new(
  base_url : String,
  max_metadata_bytes~ : Int32 = 1048576,
  max_chunk_bytes~ : Int32 = 67108864,
  max_chunks~ : Int32 = 1024,
  max_cache_bytes~ : Int32 = 67108864,
  max_cache_entries~ : Int32 = 4096,
  read_limits~ : @store.ReadLimits = @store.ReadLimits::defaults(),
  max_hydration_bytes~ : Int32 = 67108864,
  request_timeout_ms~ : Int32 = 30000,
) -> HttpStore? {
  if !(base_url.has_prefix("http://") || base_url.has_prefix("https://")) ||
    base_url.contains("?") ||
    base_url.contains("#") ||
    max_metadata_bytes <= 0 ||
    max_chunk_bytes <= 0 ||
    max_chunks <= 0 ||
    max_cache_bytes < 0 ||
    max_cache_entries <= 0 ||
    max_hydration_bytes <= 0 ||
    request_timeout_ms <= 0 {
    return None
  }
  Some({
    base_url,
    max_metadata_bytes,
    max_chunk_bytes,
    max_chunks,
    max_cache_bytes,
    max_cache_entries,
    cache: Map([]),
    cache_bytes: 0,
    cache_entries: 0,
    tick: 0UL,
    limits: read_limits,
    max_hydration_bytes,
    request_timeout_ms,
    get_headers: None,
  })
}

///|
/// Configure per-request headers for authenticated read-only endpoints.
/// The callback receives the full URL, optional Range and optional If-Match.
/// Returning None rejects the request before network I/O.
/// Changing the provider starts a fresh cache so an earlier authorization
/// context cannot bypass the new provider.
pub fn HttpStore::with_get_headers(
  self : HttpStore,
  provider : (String, String?, String?) -> Map[String, String]?,
) -> HttpStore {
  {
    ..self,
    get_headers: Some(provider),
    cache: Map([]),
    cache_bytes: 0,
    cache_entries: 0,
    tick: 0UL,
  }
}

///|
fn HttpStore::headers(
  self : HttpStore,
  url : String,
  range : String?,
  if_match : String?,
) -> Map[String, String]? {
  let headers = match self.get_headers {
    Some(provider) => {
      guard provider(url, range, if_match) is Some(headers) else { return None }
      headers
    }
    None => Map([])
  }
  headers["Accept-Encoding"] = "identity"
  if range is Some(value) {
    headers["Range"] = value
  }
  if if_match is Some(value) {
    headers["If-Match"] = value
  }
  Some(headers)
}

///|
priv enum FetchResult {
  Found(Bytes)
  Missing
  Failed(@store.AccessError)
  Transient(@store.AccessError)
}

///|
priv enum RangeResult {
  RangeFound(Bytes, Int64, String?)
  RangeMissing
  RangeFailed(@store.AccessError)
  RangeTransient(@store.AccessError)
}

///|
fn response_error(key : String, status : Int32) -> @store.AccessError {
  match status {
    401 | 403 => @store.Authentication(key, status)
    412 => @store.Conflict(key)
    _ => @store.HttpStatus(key, status)
  }
}

///|
fn content_range(value : String) -> (Int64, Int64, Int64)? {
  if !value.has_prefix("bytes ") {
    return None
  }
  guard value[6:].split_once("/") is Some((bounds, total_raw)) else {
    return None
  }
  guard bounds.split_once("-") is Some((first_raw, last_raw)) else {
    return None
  }
  let first = @string.parse_int64(first_raw) catch { _ => return None }
  let last = @string.parse_int64(last_raw) catch { _ => return None }
  let total = @string.parse_int64(total_raw) catch { _ => return None }
  if first < 0 || last < first || total <= last {
    return None
  }
  Some((first, last, total))
}

///|
fn HttpStore::next_tick(self : HttpStore) -> UInt64 {
  self.tick += 1UL
  self.tick
}

///|
fn HttpStore::cached(
  self : HttpStore,
  key : String,
  limit : Int32,
) -> FetchResult? {
  guard self.cache.get(key) is Some(entry) else { return None }
  if entry.bytes.length() > limit {
    return Some(Failed(@store.LimitExceeded("object", key)))
  }
  self.cache.set(key, { bytes: entry.bytes, access: self.next_tick(), })
  Some(Found(entry.bytes))
}

///|
fn HttpStore::cache_found(
  self : HttpStore,
  key : String,
  bytes : Bytes,
) -> Unit {
  if self.max_cache_bytes == 0 ||
    bytes.length() == 0 ||
    bytes.length() > self.max_cache_bytes {
    return
  }
  if self.cache.get(key) is Some(previous) {
    self.cache_bytes -= previous.bytes.length()
    self.cache_entries -= 1
    self.cache.remove(key)
  }
  let available = self.max_cache_bytes - bytes.length()
  while self.cache_bytes > available ||
        self.cache_entries >= self.max_cache_entries {
    let mut oldest : String? = None
    let mut oldest_access = 18446744073709551615UL
    for candidate, entry in self.cache {
      if entry.access <= oldest_access {
        oldest = Some(candidate)
        oldest_access = entry.access
      }
    }
    guard oldest is Some(victim) else { return }
    guard self.cache.get(victim) is Some(entry) else { return }
    self.cache_bytes -= entry.bytes.length()
    self.cache_entries -= 1
    self.cache.remove(victim)
  }
  self.cache.set(key, { bytes, access: self.next_tick(), })
  self.cache_bytes += bytes.length()
  self.cache_entries += 1
}

///|
fn hex_digit(nibble : Int32) -> Char {
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
fn HttpStore::key_url(self : HttpStore, key : String) -> String? {
  guard encode_key(key) is Some(encoded) else { return None }
  Some(
    if self.base_url.has_suffix("/") {
      "\{self.base_url}\{encoded}"
    } else {
      "\{self.base_url}/\{encoded}"
    },
  )
}

///|
async fn HttpStore::fetch_uncached(
  self : HttpStore,
  key : String,
  limit : Int32,
) -> FetchResult {
  if self.cached(key, limit) is Some(result) {
    return result
  }
  guard self.key_url(key) is Some(url) else {
    return Failed(@store.InvalidPath(key))
  }
  guard self.headers(url, None, None) is Some(headers) else {
    return Failed(@store.HeaderRejected(key))
  }
  let (response, client) = @client_http.get_stream(url, headers~) catch {
    _ => return Transient(@store.Transport(key))
  }
  defer client.close()
  if response.headers.get("content-encoding") is Some(encoding) &&
    encoding.to_lower() != "identity" {
    return Failed(@store.Protocol(key, "content-encoding"))
  }
  match response.code {
    404 => Missing
    200 => {
      let output : Array[Byte] = []
      for ;; {
        let next = client.read_some(max_len=32768) catch {
          _ => return Transient(@store.Transport(key))
        }
        match next {
          None => {
            let found = Bytes::from_array(output)
            self.cache_found(key, found)
            return Found(found)
          }
          Some(bytes) => {
            if bytes.length() > limit - output.length() {
              return Failed(@store.LimitExceeded("object", key))
            }
            output.append(bytes.to_array()[:])
          }
        }
      }
      Failed(@store.Protocol(key, "body"))
    }
    429 | 500 | 502 | 503 | 504 => Transient(response_error(key, response.code))
    _ => Failed(response_error(key, response.code))
  }
}

///|
async fn HttpStore::fetch(
  self : HttpStore,
  key : String,
  limit : Int32,
) -> FetchResult {
  for attempt in 0..<2 {
    let result = @async.with_timeout_opt(self.request_timeout_ms, async fn() {
      self.fetch_uncached(key, limit)
    })
    match result {
      Some(Found(value)) => return Found(value)
      Some(Missing) => return Missing
      Some(Failed(error)) => return Failed(error)
      Some(Transient(error)) => {
        if attempt == 1 {
          return Failed(error)
        }
        @async.sleep(50)
      }
      None => {
        if attempt == 1 {
          return Failed(@store.Timeout(key))
        }
        @async.sleep(50)
      }
    }
  }
  Failed(@store.Transport(key))
}

///|
/// Strict partial read: a server that ignores Range or lies about its extent
/// is an error, never a missing chunk or a successful truncated shard.
async fn HttpStore::fetch_range_once(
  self : HttpStore,
  key : String,
  range : String,
  limit : Int32,
  expected_etag : String?,
) -> RangeResult {
  guard self.key_url(key) is Some(url) else {
    return RangeFailed(@store.InvalidPath(key))
  }
  guard self.headers(url, Some(range), expected_etag) is Some(headers) else {
    return RangeFailed(@store.HeaderRejected(key))
  }
  let (response, client) = @client_http.get_stream(url, headers~) catch {
    _ => return RangeTransient(@store.Transport(key))
  }
  defer client.close()
  if response.headers.get("content-encoding") is Some(encoding) &&
    encoding.to_lower() != "identity" {
    return RangeFailed(@store.Protocol(key, "content-encoding"))
  }
  if response.code == 404 {
    return RangeMissing
  }
  if response.code == 429 ||
    response.code == 500 ||
    response.code == 502 ||
    response.code == 503 ||
    response.code == 504 {
    return RangeTransient(response_error(key, response.code))
  }
  if response.code != 206 {
    return RangeFailed(
      if response.code == 200 {
        @store.Protocol(key, "server ignored Range")
      } else {
        response_error(key, response.code)
      },
    )
  }
  guard response.headers.get("content-range") is Some(raw_range) else {
    return RangeFailed(@store.Protocol(key, "missing Content-Range"))
  }
  guard content_range(raw_range) is Some((first, last, total)) else {
    return RangeFailed(@store.Protocol(key, "invalid Content-Range"))
  }
  let length = last - first + 1L
  if length <= 0L || length > limit.to_int64() {
    return RangeFailed(@store.Protocol(key, "range length"))
  }
  if range.has_prefix("bytes=-") {
    let suffix = @string.parse_int64(range[7:]) catch {
      _ => return RangeFailed(@store.Protocol(key, "suffix range"))
    }
    if suffix != length || last != total - 1L {
      return RangeFailed(@store.Protocol(key, "suffix range mismatch"))
    }
  } else {
    guard range[6:].split_once("-") is Some((a, b)) else {
      return RangeFailed(@store.Protocol(key, "range"))
    }
    let requested_first = @string.parse_int64(a) catch {
      _ => return RangeFailed(@store.Protocol(key, "range"))
    }
    let requested_last = @string.parse_int64(b) catch {
      _ => return RangeFailed(@store.Protocol(key, "range"))
    }
    if first != requested_first || last != requested_last {
      return RangeFailed(@store.Protocol(key, "range mismatch"))
    }
  }
  let output : Array[Byte] = []
  for ;; {
    let next = client.read_some(max_len=32768) catch {
      _ => return RangeTransient(@store.Transport(key))
    }
    match next {
      None => {
        if output.length().to_int64() != length {
          return RangeFailed(@store.Protocol(key, "truncated range"))
        }
        return RangeFound(
          Bytes::from_array(output),
          total,
          response.headers.get("etag"),
        )
      }
      Some(bytes) => {
        if bytes.length() > limit - output.length() ||
          bytes.length().to_int64() > length - output.length().to_int64() {
          return RangeFailed(@store.Protocol(key, "oversized range"))
        }
        output.append(bytes.to_array()[:])
      }
    }
  }
  RangeFailed(@store.Protocol(key, "body"))
}

///|
async fn HttpStore::fetch_range(
  self : HttpStore,
  key : String,
  range : String,
  limit : Int32,
  expected_etag : String?,
) -> RangeResult {
  for attempt in 0..<2 {
    let result = @async.with_timeout_opt(self.request_timeout_ms, async fn() {
      self.fetch_range_once(key, range, limit, expected_etag)
    })
    match result {
      Some(RangeFound(bytes, total, etag)) =>
        return RangeFound(bytes, total, etag)
      Some(RangeMissing) => return RangeMissing
      Some(RangeFailed(error)) => return RangeFailed(error)
      Some(RangeTransient(error)) => {
        if attempt == 1 {
          return RangeFailed(error)
        }
        @async.sleep(50)
      }
      None => {
        if attempt == 1 {
          return RangeFailed(@store.Timeout(key))
        }
        @async.sleep(50)
      }
    }
  }
  RangeFailed(@store.Transport(key))
}

///|
async fn HttpStore::object_result(
  self : HttpStore,
  key : String,
  limit : Int32,
) -> Result[Bytes?, @store.AccessError] {
  match self.fetch(key, limit) {
    Found(bytes) => Ok(Some(bytes))
    Missing => Ok(None)
    Failed(error) | Transient(error) => Err(error)
  }
}

///|
async fn HttpStore::node_document_result(
  self : HttpStore,
  path : String,
) -> Result[(@hierarchy.Node, String), @store.AccessError] {
  if !@hierarchy.discovery_path(path) {
    return Err(@store.InvalidPath(path))
  }
  let prefix = if path == "" { "" } else { "\{path}/" }
  let limit = if self.max_metadata_bytes < self.limits.max_metadata_bytes() {
    self.max_metadata_bytes
  } else {
    self.limits.max_metadata_bytes()
  }
  let v2_array = match self.object_result("\{prefix}.zarray", limit) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let v2_group = match self.object_result("\{prefix}.zgroup", limit) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let v3 = match self.object_result("\{prefix}zarr.json", limit) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  let node = match
    @hierarchy.classify_node(path, v2_array, v2_group, v3, self.limits) {
    Ok(Some(node)) => node
    Ok(None) => return Err(@store.NotFound(path))
    Err(error) => return Err(error)
  }
  let bytes = if node.format == @metadata.V3 {
    v3
  } else if node.kind == @hierarchy.ArrayNode {
    v2_array
  } else {
    v2_group
  }
  guard bytes is Some(bytes) else { return Err(@store.InvalidMetadata(path)) }
  let raw = @utf8.decode(bytes[:]) catch {
    _ => return Err(@store.InvalidMetadata(path))
  }
  Ok((node, raw))
}

///|
/// Discover one explicit group/array metadata node, preserving failure causes.
pub async fn HttpStore::open_node_result(
  self : HttpStore,
  path : String,
) -> Result[@hierarchy.Node, @store.AccessError] {
  match self.node_document_result(path) {
    Ok((node, _)) => Ok(node)
    Err(error) => Err(error)
  }
}

///|
async fn HttpStore::load_array_result(
  self : HttpStore,
  path : String,
) -> Result[
  (@metadata.Format, String, @metadata.ArrayMetadata),
  @store.AccessError,
] {
  let (node, raw) = match self.node_document_result(path) {
    Ok(value) => value
    Err(error) => return Err(error)
  }
  if node.kind != @hierarchy.ArrayNode {
    return Err(@store.NotArray(path))
  }
  guard @metadata.parse_array_metadata(raw) is Some(outer) else {
    return Err(@store.InvalidMetadata(path))
  }
  guard @shard.prepare(outer) is Some(metadata) else {
    return Err(@store.UnsupportedMetadata(path))
  }
  if !self.limits.allows_array(metadata) {
    return Err(@store.LimitExceeded("array", path))
  }
  Ok((node.format, raw, metadata))
}

///|
/// Discover a remote array's validated logical shape, dtype and inner-chunk
/// shape without fetching chunk data. For sharded v3 arrays the returned
/// metadata is an inner-chunk view, consistent with FileStore::open_array.
pub async fn HttpStore::open_array(
  self : HttpStore,
  path : String,
) -> @metadata.ArrayMetadata? {
  guard @chunk.normalized_path(path, @metadata.V2) is Some(path) else {
    return None
  }
  match self.open_array_result(path) {
    Ok(metadata) => Some(metadata)
    Err(_) => None
  }
}

///|
pub async fn HttpStore::open_array_result(
  self : HttpStore,
  path : String,
) -> Result[@metadata.ArrayMetadata, @store.AccessError] {
  match self.load_array_result(path) {
    Ok((_, _, metadata)) => Ok(metadata)
    Err(error) => Err(error)
  }
}

///|
/// Download the array metadata and only chunks touched by a bounded region.
/// The returned MemoryStore can be opened with typed functions in `array/`.
/// Missing chunks retain their declared fill value; HTTP failures do not.
pub async fn HttpStore::hydrate_region(
  self : HttpStore,
  path : String,
  origin : Array[Int32],
  extent : Array[Int32],
) -> @store.MemoryStore? {
  guard @chunk.normalized_path(path, @metadata.V2) is Some(path) else {
    return None
  }
  match self.hydrate_region_result(path, origin, extent) {
    Ok(scratch) => Some(scratch)
    Err(_) => None
  }
}

///|
/// Hydrate encoded bytes with per-call diagnostics. This does not decode the
/// selected codec payloads; typed array decoding remains a separate operation.
pub async fn HttpStore::hydrate_region_result(
  self : HttpStore,
  path : String,
  origin : Array[Int32],
  extent : Array[Int32],
) -> Result[@store.MemoryStore, @store.AccessError] {
  let (format, raw, metadata) = match self.load_array_result(path) {
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
  self.hydrate_prepared(path, origin, extent, format, scratch_raw, metadata)
}

///|
async fn HttpStore::hydrate_prepared(
  self : HttpStore,
  path : String,
  origin : Array[Int32],
  extent : Array[Int32],
  format : @metadata.Format,
  scratch_raw : String,
  metadata : @metadata.ArrayMetadata,
) -> Result[@store.MemoryStore, @store.AccessError] {
  guard @chunk.region_len(metadata, origin, extent) is Some(length) else {
    return Err(@store.InvalidRegion(path))
  }
  if !self.limits.allows_region(metadata, origin, extent) {
    return Err(@store.LimitExceeded("region", path))
  }
  let scratch = @store.MemoryStore::new(read_limits=self.limits)
  if !scratch.put_array_metadata(format, path, scratch_raw) {
    return Err(@store.InvalidMetadata(path))
  }
  if length == 0 {
    return Ok(scratch)
  }
  let mut count = 1
  for i in 0..<origin.length() {
    let side = metadata.chunk_shape[i]
    if side <= 0 {
      return Err(@store.InvalidMetadata(path))
    }
    let first = origin[i] / side
    let last = (origin[i] + extent[i] - 1) / side
    let span = last - first + 1
    if count > self.max_chunks / span {
      return Err(@store.LimitExceeded("chunks", path))
    }
    count *= span
  }
  guard @chunk.region_chunks(
      metadata,
      origin,
      extent,
      max_chunks=self.limits.max_chunks(),
    )
    is Some(pieces) else {
    return Err(@store.LimitExceeded("chunks", path))
  }
  let chunk_limit = if self.max_chunk_bytes < self.limits.max_chunk_bytes() {
    self.max_chunk_bytes
  } else {
    self.limits.max_chunk_bytes()
  }
  let mut hydrated = 0
  let indices : Map[String, @shard.ValidatedIndex] = Map([])
  let shard_sizes : Map[String, Int64] = Map([])
  let shard_etags : Map[String, String] = Map([])
  let absent_shards : Map[String, Bool] = Map([])
  for piece in pieces {
    let fetched = if metadata.sharding is Some(layout) {
      guard @shard.coordinates(metadata, piece.coordinates)
        is Some((outer_coords, within)) else {
        return Err(@store.InvalidShard(path))
      }
      guard @chunk.shard_key(metadata, outer_coords, path) is Some(key) else {
        return Err(@store.InvalidPath(path))
      }
      if absent_shards.get(key) is Some(_) {
        Missing
      } else {
        let index = match indices.get(key) {
          Some(index) => index
          None => {
            if layout.index_size > self.max_hydration_bytes - hydrated {
              return Err(@store.LimitExceeded("hydration", key))
            }
            let range = if layout.index_at_start {
              "bytes=0-\{layout.index_size - 1}"
            } else {
              "bytes=-\{layout.index_size}"
            }
            match self.fetch_range(key, range, layout.index_size, None) {
              RangeMissing => {
                absent_shards[key] = true
                continue
              }
              RangeFailed(error) | RangeTransient(error) => return Err(error)
              RangeFound(bytes, size, etag) => {
                hydrated += bytes.length()
                guard @shard.validate_index(layout, bytes, size)
                  is Some(validated) else {
                  return Err(@store.InvalidShard(key))
                }
                indices[key] = validated
                shard_sizes[key] = size
                if etag is Some(tag) {
                  shard_etags[key] = tag
                }
                validated
              }
            }
          }
        }
        match index.entry(within) {
          @shard.Absent => Missing
          @shard.Invalid => Failed(@store.InvalidShard(key))
          @shard.Data(at, size) => {
            if size > chunk_limit || size > self.max_hydration_bytes - hydrated {
              return Err(@store.LimitExceeded("hydration", key))
            }
            let last = at + size.to_int64() - 1L
            match
              self.fetch_range(
                key,
                "bytes=\{at}-\{last}",
                size,
                shard_etags.get(key),
              ) {
              RangeFound(bytes, total, _) => {
                if shard_sizes.get(key) != Some(total) {
                  return Err(@store.Conflict(key))
                }
                Found(bytes)
              }
              RangeMissing => Failed(@store.Conflict(key))
              RangeFailed(error) | RangeTransient(error) => Failed(error)
            }
          }
        }
      }
    } else {
      guard @chunk.chunk_key(metadata, piece.coordinates, path) is Some(key) else {
        return Err(@store.InvalidPath(path))
      }
      self.fetch(key, chunk_limit)
    }
    match fetched {
      Found(chunk) => {
        if chunk.length() > self.max_hydration_bytes - hydrated {
          return Err(@store.LimitExceeded("hydration", path))
        }
        hydrated += chunk.length()
        if !scratch.put_chunk(metadata, piece.coordinates, path, chunk) {
          return Err(@store.InvalidMetadata(path))
        }
      }
      Missing => ()
      Failed(error) | Transient(error) => return Err(error)
    }
  }
  Ok(scratch)
}
