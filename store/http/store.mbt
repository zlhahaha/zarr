///|
/// Read-only HTTP access to a Zarr hierarchy. Each hydration call fetches
/// only metadata and the chunks intersecting its requested rectangle.
pub struct HttpStore {
  base_url : String
  max_metadata_bytes : Int
  max_chunk_bytes : Int
  max_chunks : Int
  max_cache_bytes : Int
  max_cache_entries : Int
  cache : Map[String, CacheEntry]
  mut cache_bytes : Int
  mut cache_entries : Int
  mut tick : UInt64
  limits : @store.ReadLimits
  max_hydration_bytes : Int
  request_timeout_ms : Int
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
  max_metadata_bytes? : Int = 1048576,
  max_chunk_bytes? : Int = 67108864,
  max_chunks? : Int = 1024,
  max_cache_bytes? : Int = 67108864,
  max_cache_entries? : Int = 4096,
  read_limits? : @store.ReadLimits = @store.ReadLimits::defaults(),
  max_hydration_bytes? : Int = 67108864,
  request_timeout_ms? : Int = 30000,
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
pub fn HttpStore::with_get_headers(
  self : HttpStore,
  provider : (String, String?, String?) -> Map[String, String]?,
) -> HttpStore {
  { ..self, get_headers: Some(provider), }
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
  Failed
  Transient
}

///|
priv enum RangeResult {
  RangeFound(Bytes, Int64, String?)
  RangeMissing
  RangeFailed
  RangeTransient
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
  limit : Int,
) -> FetchResult? {
  guard self.cache.get(key) is Some(entry) else { return None }
  if entry.bytes.length() > limit {
    return Some(Failed)
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
  limit : Int,
) -> FetchResult {
  if self.cached(key, limit) is Some(result) {
    return result
  }
  guard self.key_url(key) is Some(url) else { return Failed }
  guard self.headers(url, None, None) is Some(headers) else { return Failed }
  let (response, client) = @client_http.get_stream(url, headers~) catch {
    _ => return Transient
  }
  defer client.close()
  if response.headers.get("content-encoding") is Some(encoding) &&
    encoding.to_lower() != "identity" {
    return Failed
  }
  match response.code {
    404 => Missing
    200 => {
      let output : Array[Byte] = []
      for ;; {
        let next = client.read_some(max_len=32768) catch {
          _ => return Transient
        }
        match next {
          None => {
            let found = Bytes::from_array(output)
            self.cache_found(key, found)
            return Found(found)
          }
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
    429 | 500 | 502 | 503 | 504 => Transient
    _ => Failed
  }
}

///|
async fn HttpStore::fetch(
  self : HttpStore,
  key : String,
  limit : Int,
) -> FetchResult {
  for attempt in 0..<2 {
    let result = @async.with_timeout_opt(self.request_timeout_ms, async fn() {
      self.fetch_uncached(key, limit)
    })
    match result {
      Some(Found(value)) => return Found(value)
      Some(Missing) => return Missing
      Some(Failed) => return Failed
      Some(Transient) | None => if attempt == 0 { @async.sleep(50) }
    }
  }
  Failed
}

///|
/// Strict partial read: a server that ignores Range or lies about its extent
/// is an error, never a missing chunk or a successful truncated shard.
async fn HttpStore::fetch_range_once(
  self : HttpStore,
  key : String,
  range : String,
  limit : Int,
  expected_etag : String?,
) -> RangeResult {
  guard self.key_url(key) is Some(url) else { return RangeFailed }
  guard self.headers(url, Some(range), expected_etag) is Some(headers) else {
    return RangeFailed
  }
  let (response, client) = @client_http.get_stream(url, headers~) catch {
    _ => return RangeTransient
  }
  defer client.close()
  if response.headers.get("content-encoding") is Some(encoding) &&
    encoding.to_lower() != "identity" {
    return RangeFailed
  }
  if response.code == 404 {
    return RangeMissing
  }
  if response.code == 429 ||
    response.code == 500 ||
    response.code == 502 ||
    response.code == 503 ||
    response.code == 504 {
    return RangeTransient
  }
  if response.code != 206 {
    return RangeFailed
  }
  guard response.headers.get("content-range") is Some(raw_range) else {
    return RangeFailed
  }
  guard content_range(raw_range) is Some((first, last, total)) else {
    return RangeFailed
  }
  let length = last - first + 1L
  if length <= 0L || length > limit.to_int64() {
    return RangeFailed
  }
  if range.has_prefix("bytes=-") {
    let suffix = @string.parse_int64(range[7:]) catch {
      _ => return RangeFailed
    }
    if suffix != length || last != total - 1L {
      return RangeFailed
    }
  } else {
    guard range[6:].split_once("-") is Some((a, b)) else { return RangeFailed }
    let requested_first = @string.parse_int64(a) catch {
      _ => return RangeFailed
    }
    let requested_last = @string.parse_int64(b) catch {
      _ => return RangeFailed
    }
    if first != requested_first || last != requested_last {
      return RangeFailed
    }
  }
  let output : Array[Byte] = []
  for ;; {
    let next = client.read_some(max_len=32768) catch {
      _ => return RangeTransient
    }
    match next {
      None => {
        if output.length().to_int64() != length {
          return RangeFailed
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
          return RangeFailed
        }
        output.append(bytes.to_array()[:])
      }
    }
  }
  RangeFailed
}

///|
async fn HttpStore::fetch_range(
  self : HttpStore,
  key : String,
  range : String,
  limit : Int,
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
      Some(RangeFailed) => return RangeFailed
      Some(RangeTransient) | None => if attempt == 0 { @async.sleep(50) }
    }
  }
  RangeFailed
}

///|
async fn HttpStore::load_array(
  self : HttpStore,
  path : String,
) -> (@metadata.Format, String, @metadata.ArrayMetadata)? {
  guard @chunk.array_metadata_key(@metadata.V2, path) is Some(v2_key) else {
    return None
  }
  guard @chunk.array_metadata_key(@metadata.V3, path) is Some(v3_key) else {
    return None
  }
  let metadata_limit = if self.max_metadata_bytes <
    self.limits.max_metadata_bytes() {
    self.max_metadata_bytes
  } else {
    self.limits.max_metadata_bytes()
  }
  let v2 = self.fetch(v2_key, metadata_limit)
  let v3 = self.fetch(v3_key, metadata_limit)
  let (format, bytes) = match (v2, v3) {
    (Found(bytes), Missing) => (@metadata.V2, bytes)
    (Missing, Found(bytes)) => (@metadata.V3, bytes)
    _ => return None
  }
  if format == @metadata.V2 {
    guard @chunk.group_metadata_key(format, path) is Some(group_key) else {
      return None
    }
    match self.fetch(group_key, metadata_limit) {
      Missing => ()
      _ => return None
    }
  }
  if !self.limits.allows_metadata(bytes) {
    return None
  }
  let raw = @utf8.decode(bytes[:]) catch { _ => return None }
  guard @metadata.parse_array_metadata(raw) is Some(outer) else { return None }
  if outer.format != format {
    return None
  }
  guard @shard.prepare(outer) is Some(metadata) else { return None }
  if !self.limits.allows_array(metadata) {
    return None
  }
  Some((format, raw, metadata))
}

///|
/// Discover a remote array's validated logical shape, dtype and inner-chunk
/// shape without fetching chunk data. For sharded v3 arrays the returned
/// metadata is an inner-chunk view, consistent with FileStore::open_array.
pub async fn HttpStore::open_array(
  self : HttpStore,
  path : String,
) -> @metadata.ArrayMetadata? {
  guard self.load_array(path) is Some((_, _, metadata)) else { return None }
  Some(metadata)
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
  guard self.load_array(path) is Some((format, raw, metadata)) else {
    return None
  }
  if !self.limits.allows_region(metadata, origin, extent) {
    return None
  }
  guard @chunk.region_len(metadata, origin, extent) is Some(length) else {
    return None
  }
  let scratch = @store.MemoryStore::new(read_limits=self.limits)
  let scratch_raw = if metadata.sharding is Some(_) {
    guard @shard.inner_metadata_json(raw) is Some(inner) else { return None }
    inner
  } else {
    raw
  }
  if !scratch.put_array_metadata(format, path, scratch_raw) {
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
  guard @chunk.region_chunks(
      metadata,
      origin,
      extent,
      max_chunks=self.limits.max_chunks(),
    )
    is Some(pieces) else {
    return None
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
        return None
      }
      guard @chunk.shard_key(metadata, outer_coords, path) is Some(key) else {
        return None
      }
      if absent_shards.get(key) is Some(_) {
        Missing
      } else {
        let index = match indices.get(key) {
          Some(index) => index
          None => {
            if layout.index_size > self.max_hydration_bytes - hydrated {
              return None
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
              RangeFailed | RangeTransient => return None
              RangeFound(bytes, size, etag) => {
                hydrated += bytes.length()
                guard @shard.validate_index(layout, bytes, size)
                  is Some(validated) else {
                  return None
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
          @shard.Invalid => Failed
          @shard.Data(at, size) => {
            if size > chunk_limit || size > self.max_hydration_bytes - hydrated {
              return None
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
                  return None
                }
                Found(bytes)
              }
              RangeMissing | RangeFailed | RangeTransient => Failed
            }
          }
        }
      }
    } else {
      guard @chunk.chunk_key(metadata, piece.coordinates, path) is Some(key) else {
        return None
      }
      self.fetch(key, chunk_limit)
    }
    match fetched {
      Found(chunk) => {
        if chunk.length() > self.max_hydration_bytes - hydrated {
          return None
        }
        hydrated += chunk.length()
        if !scratch.put_chunk(metadata, piece.coordinates, path, chunk) {
          return None
        }
      }
      Missing => ()
      Failed | Transient => return None
    }
  }
  Some(scratch)
}
