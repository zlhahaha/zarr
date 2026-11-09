///|
fn dimension(raw : String, positive : Bool) -> Int32 {
  let parsed = @json.parse(raw) catch {
    _ => abort("integer coordinate required")
  }
  guard parsed is Number(n, ..) else { abort("integer coordinate required") }
  if n < (if positive { 1.0 } else { 0.0 }) ||
    n > 2147483647.0 ||
    n != n.to_int().to_double() {
    abort("coordinate out of range")
  }
  n.to_int()
}

///|
fn credentials() -> @s3.Credentials? {
  match
    (@env.get_env_var("ZARR_ACCESS_KEY"), @env.get_env_var("ZARR_SECRET_KEY")) {
    (None, None) => None
    (Some(key), Some(secret)) => {
      let result = match @env.get_env_var("ZARR_SESSION_TOKEN") {
        Some(token) => @s3.Credentials::new(key, secret, session_token=token)
        None => @s3.Credentials::new(key, secret)
      }
      guard result is Some(value) else {
        abort("invalid explicit S3 credentials")
      }
      Some(value)
    }
    _ => abort("both ZARR_ACCESS_KEY and ZARR_SECRET_KEY are required")
  }
}

///|
async fn input_reader(
  source : String,
  path : String,
  origin : Array[Int32],
  extent : Array[Int32],
) -> @reader.Reader[Byte] {
  if source.has_prefix("https://") || source.has_prefix("http://") {
    guard @http.HttpStore::new(source) is Some(store) else {
      abort("HTTP source configuration")
    }
    guard @remote.Source::http(store).open_u8(path, origin, extent, [8, 32, 32])
      is Ok(reader) else {
      abort("HTTP metadata/ROI")
    }
    return reader
  }
  if source.has_prefix("s3://") {
    let tail = source[5:].to_owned()
    let (bucket, prefix) = match tail.split_once("/") {
      Some((bucket, prefix)) => (bucket.to_owned(), prefix.to_owned())
      None => (tail, "")
    }
    let region = @env.get_env_var("ZARR_REGION").unwrap_or("us-east-1")
    let endpoint = @env.get_env_var("ZARR_ENDPOINT").unwrap_or("")
    let allow_insecure_http = @env.get_env_var("ZARR_ALLOW_INSECURE_HTTP") ==
      Some("true")
    let store = match credentials() {
      Some(creds) =>
        @s3.S3Store::new(
          bucket,
          region,
          prefix~,
          endpoint~,
          allow_insecure_http~,
          credentials=creds,
        )
      None => @s3.S3Store::new(bucket, region, prefix~, endpoint~)
    }
    guard store is Some(store) else { abort("S3 source configuration") }
    guard @remote.Source::s3(store).open_u8(path, origin, extent, [8, 32, 32])
      is Ok(reader) else {
      abort("S3 metadata/ROI")
    }
    return reader
  }
  guard @fs.FileStore::new(source) is Some(store) else {
    abort("local source configuration")
  }
  guard store.open_array(path) is Some(metadata) else {
    abort("local metadata")
  }
  guard store.open_u8(path) is Some(array) else {
    abort("3D uint8 input required")
  }
  guard @reader.Reader::new(metadata.shape, origin, extent, [8, 32, 32], tile => {
      match array.read_region(tile.origin, tile.extent) {
        Some(bytes) => Ok(bytes.to_array())
        None => Err(@store.InvalidRegion("source"))
      }
    })
    is Some(reader) else {
    abort("local ROI")
  }
  reader
}

///|
/// Crop uint8 input, scale to float32 [0,1], write independent v3 shards.
/// The same source works as a local path, HTTP root, or s3://bucket/prefix.
async fn main {
  let args = @env.args()
  if args.length() != 10 {
    abort("volume_pipeline INPUT ARRAY_PATH OUTPUT O0 O1 O2 N0 N1 N2")
  }
  let origin = Array::makei(3, i => dimension(args[4 + i], false))
  let extent = Array::makei(3, i => dimension(args[7 + i], true))
  let reader = input_reader(args[1], args[2], origin, extent)
  let first = match reader.next() {
    Ok(Some(tile)) => tile
    _ => abort("first input tile failed; expected supported uint8 data")
  }
  guard @fs.FileStore::new(args[3]) is Some(output) else {
    abort("output root")
  }
  guard output.create_sharded_f32(
      "",
      extent,
      [2, 16, 16],
      [8, 32, 32],
      0.0F,
      compression=@codec.Zstd(3),
    )
    is Some(array) else {
    abort("new output required; existing arrays/groups are never overwritten")
  }
  let histogram = Array::make(256, 0L)
  let mut count = 0L
  let mut checksum = 0L
  let mut shard_count = 0
  let mut pending = Some(first)
  while true {
    let tile = match pending {
      Some(tile) => {
        pending = None
        tile
      }
      None =>
        match reader.next() {
          Ok(Some(tile)) => tile
          Ok(None) => break
          Err(_) => abort("input tile failed; output is incomplete")
        }
    }
    let coords = Array::makei(3, i => {
      (tile.origin[i] - origin[i]) / (if i == 0 { 8 } else { 32 })
    })
    let values = tile.values.map(value => {
      let n = value.to_int()
      histogram[n] += 1L
      count += 1L
      checksum += n.to_int64()
      Float::from_int(n) / 255.0
    })
    if !array.write_shard(coords, values) {
      abort("output shard failed; output is incomplete")
    }
    shard_count += 1
  }
  let attrs = Json::object(
    Map([
      (
        "processing",
        Json::object(
          Map([
            ("operation", Json::string("uint8_to_float32")),
            (
              "roi_origin",
              Json::array(origin.map(n => Json::number(n.to_double()))),
            ),
            (
              "roi_shape",
              Json::array(extent.map(n => Json::number(n.to_double()))),
            ),
            ("scale", Json::number(1.0 / 255.0)),
            (
              "axis_order",
              Json::string("preserved; no physical-coordinate interpretation"),
            ),
          ]),
        ),
      ),
    ]),
  )
  if !output.put_attributes(@metadata.V3, "", attrs.stringify()) {
    abort("output provenance failed")
  }
  let bins = histogram.map(n => n.to_string()).join(",")
  println(
    "{\"voxels\":\{count},\"input_checksum\":\{checksum},\"shards\":\{shard_count},\"histogram\":[\{bins}]}",
  )
}
