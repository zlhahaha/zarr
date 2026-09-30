///|
extern "C" fn wall_clock_seconds() -> Int64 = "zarr_s3_unix_seconds"

///|
/// Explicit credentials for S3 Signature Version 4. Keep these outside logs
/// and repository files; temporary session credentials may include a token.
pub struct Credentials {
  access_key : String
  secret_key : String
  session_token : String?
}

///|
pub fn Credentials::new(
  access_key : String,
  secret_key : String,
  session_token? : String,
) -> Credentials? {
  if access_key == "" ||
    secret_key == "" ||
    access_key.contains("\r") ||
    access_key.contains("\n") ||
    secret_key.contains("\r") ||
    secret_key.contains("\n") {
    return None
  }
  if session_token is Some(value) &&
    (value == "" || value.contains("\r") || value.contains("\n")) {
    return None
  }
  Some({ access_key, secret_key, session_token, })
}

///|
fn valid_label(value : String) -> Bool {
  if value == "" {
    return false
  }
  for char in value {
    let code = char.to_int()
    if !(code >= 97 && code <= 122) &&
      !(code >= 48 && code <= 57) &&
      code != 45 &&
      code != 46 {
      return false
    }
  }
  true
}

///|
fn clean_prefix(value : String) -> String? {
  if value == "" {
    return Some("")
  }
  if value.has_prefix("/") ||
    value.has_suffix("/") ||
    value.contains("?") ||
    value.contains("#") {
    return None
  }
  let parts = value.split("/")
  for part in parts {
    if part == "" || part == "." || part == ".." {
      return None
    }
    for char in part {
      let code = char.to_int()
      if !(code >= 65 && code <= 90) &&
        !(code >= 97 && code <= 122) &&
        !(code >= 48 && code <= 57) &&
        code != 45 &&
        code != 95 &&
        code != 46 &&
        code != 126 {
        return None
      }
    }
  }
  Some(value)
}

///|
fn amz_timestamp() -> String? {
  let seconds = wall_clock_seconds()
  if seconds < 0L {
    return None
  }
  let value = @time.PlainDateTime::from_unix_second(
    seconds, 0, @time.utc_offset,
  ) catch {
    _ => return None
  }
  Some(
    "\{value.year().to_string().pad_start(4, '0')}\{value.month().to_string().pad_start(2, '0')}\{value.day().to_string().pad_start(2, '0')}T\{value.hour().to_string().pad_start(2, '0')}\{value.minute().to_string().pad_start(2, '0')}\{value.second().to_string().pad_start(2, '0')}Z",
  )
}

///|
fn hmac(key : BytesView, value : String) -> FixedArray[Byte] {
  @crypto.hmac(@crypto.SHA256::new(), key, @utf8.encode(value)[:])
}

///|
fn signature_headers(
  credentials : Credentials,
  region : String,
  url : String,
  range : String?,
  if_match : String?,
  stamp : String,
) -> Map[String, String]? {
  if stamp.length() != 16 ||
    stamp[8:9] != "T" ||
    stamp[15:16] != "Z" ||
    url.contains("?") ||
    url.contains("#") {
    return None
  }
  guard url.split_once("://") is Some((_, authority_path)) else { return None }
  guard authority_path.split_once("/") is Some((host, path_tail)) else {
    return None
  }
  if host == "" {
    return None
  }
  let path = "/\{path_tail}"
  let date = stamp[:8].to_owned()
  let scope = "\{date}/\{region}/s3/aws4_request"
  let empty_hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  let canonical = StringBuilder()
  let names = StringBuilder()
  canonical.write_string("host:\{host}\n")
  names.write_string("host")
  if if_match is Some(value) {
    if value.contains("\r") || value.contains("\n") {
      return None
    }
    canonical.write_string("if-match:\{value.trim()}\n")
    names.write_string(";if-match")
  }
  if range is Some(value) {
    if value.contains("\r") || value.contains("\n") {
      return None
    }
    canonical.write_string("range:\{value}\n")
    names.write_string(";range")
  }
  canonical.write_string("x-amz-content-sha256:\{empty_hash}\n")
  canonical.write_string("x-amz-date:\{stamp}\n")
  names.write_string(";x-amz-content-sha256;x-amz-date")
  if credentials.session_token is Some(token) {
    canonical.write_string("x-amz-security-token:\{token.trim()}\n")
    names.write_string(";x-amz-security-token")
  }
  let signed = names.to_string()
  let request = "GET\n\{path}\n\n\{canonical.to_string()}\n\{signed}\n\{empty_hash}"
  let request_hash = @crypto.bytes_to_hex_string(
    @crypto.sha256(@utf8.encode(request)[:]),
  )
  let to_sign = "AWS4-HMAC-SHA256\n\{stamp}\n\{scope}\n\{request_hash}"
  let date_key = hmac(@utf8.encode("AWS4\{credentials.secret_key}")[:], date)
  let region_key = hmac(date_key.unsafe_reinterpret_as_bytes(), region)
  let service_key = hmac(region_key.unsafe_reinterpret_as_bytes(), "s3")
  let signing_key = hmac(
    service_key.unsafe_reinterpret_as_bytes(),
    "aws4_request",
  )
  let signature = @crypto.bytes_to_hex_string(
    hmac(signing_key.unsafe_reinterpret_as_bytes(), to_sign),
  )
  let authorization = "AWS4-HMAC-SHA256 Credential=\{credentials.access_key}/\{scope},SignedHeaders=\{signed},Signature=\{signature}"
  let headers = Map([
    ("Authorization", authorization),
    ("x-amz-content-sha256", empty_hash),
    ("x-amz-date", stamp),
  ])
  if credentials.session_token is Some(token) {
    headers["x-amz-security-token"] = token
  }
  Some(headers)
}

///|
/// Read-only S3-compatible object-store adapter. The underlying HTTP reader
/// shares strict object and shard-range validation with HttpStore.
pub struct S3Store {
  http : @http.HttpStore
}

///|
/// Discover validated array metadata without downloading chunks. For v3
/// shards, chunk_shape describes individually readable inner chunks.
pub async fn S3Store::open_array(
  self : S3Store,
  path : String,
) -> @metadata.ArrayMetadata? {
  self.http.open_array(path)
}

///|
/// `endpoint` selects a path-style S3-compatible service, e.g. MinIO. With
/// no endpoint, an AWS regional path-style endpoint is used. Credentials are
/// optional for public buckets; no environment-variable lookup is performed.
pub fn S3Store::new(
  bucket : String,
  region : String,
  prefix? : String = "",
  endpoint? : String = "",
  credentials? : Credentials,
  read_limits? : @store.ReadLimits = @store.ReadLimits::defaults(),
  request_timeout_ms? : Int = 30000,
) -> S3Store? {
  if !valid_label(bucket) || !valid_label(region) {
    return None
  }
  guard clean_prefix(prefix) is Some(prefix) else { return None }
  if endpoint != "" &&
    (
      !(endpoint.has_prefix("https://") || endpoint.has_prefix("http://")) ||
      endpoint.contains("?") ||
      endpoint.contains("#")
    ) {
    return None
  }
  let base = if endpoint == "" {
    "https://s3.\{region}.amazonaws.com/\{bucket}"
  } else if endpoint.has_suffix("/") {
    "\{endpoint}\{bucket}"
  } else {
    "\{endpoint}/\{bucket}"
  }
  let root = if prefix == "" { base } else { "\{base}/\{prefix}" }
  guard @http.HttpStore::new(root, read_limits~, request_timeout_ms~)
    is Some(http) else {
    return None
  }
  let http = match credentials {
    None => http
    Some(creds) =>
      http.with_get_headers(fn(url, range, if_match) {
        guard amz_timestamp() is Some(stamp) else { return None }
        signature_headers(creds, region, url, range, if_match, stamp)
      })
  }
  Some({ http, })
}

///|
/// Fetch only the metadata and ordinary/sharded chunks touched by `origin` /
/// `extent`. The returned MemoryStore is a read-only snapshot of downloaded
/// bytes and can be opened with the standard typed array APIs.
pub async fn S3Store::hydrate_region(
  self : S3Store,
  path : String,
  origin : Array[Int],
  extent : Array[Int],
) -> @store.MemoryStore? {
  self.http.hydrate_region(path, origin, extent)
}
