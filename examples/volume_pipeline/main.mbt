///|
struct Timings {
  mut decode_ns : Int64
}

///|
async fn remote_reader(
  source : @remote.Source,
  path : String,
  origin : Array[Int32],
  extent : Array[Int32],
  timings : Timings,
) -> @reader.Reader[Byte] {
  guard source.open(path, origin, extent, [8, 32, 32], (memory, path, tile) => {
      let start = @metrics.time_ns()
      let values = match @array.open_u8(memory, path) {
        Some(array) =>
          array
          .read_region(tile.origin, tile.extent)
          .map(bytes => bytes.to_array())
        None => None
      }
      timings.decode_ns += @metrics.time_ns() - start
      values
    })
    is Ok(reader) else {
    abort("remote metadata/ROI")
  }
  reader
}

///|
/// Application completion protocol; this is not an array transaction or a
/// post-publication integrity proof. Generic Zarr readers ignore this marker.
async fn check_complete(path : String) -> Unit {
  guard @fs.FileStore::new(path) is Some(store) else { abort("output root") }
  guard store.get("pipeline-status.json") is Some(bytes) else {
    abort("missing completion marker; output is not accepted")
  }
  let raw = @utf8.decode(bytes[:]) catch {
    _ => abort("invalid completion marker")
  }
  let marker = @json.parse(raw) catch {
    _ => abort("invalid completion marker")
  }
  guard marker is Object(fields) &&
    fields.get("schema_version") is Some(Number(1.0, ..)) &&
    fields.get("status") is Some(String("complete")) else {
    abort("output is incomplete")
  }
  guard store.open_f32("") is Some(array) else { abort("output metadata") }
  guard array.metadata.format == @metadata.V3 &&
    array.metadata.chunk_shape == [2, 16, 16] &&
    array.metadata.sharding is Some(layout) &&
    layout.shard_shape == [8, 32, 32] else {
    abort("unexpected output shard layout")
  }
  let shape = array.metadata.shape
  guard shape.length() == 3 &&
    fields.get("shape") ==
    Some(Json::array(shape.map(n => Json::number(n.to_double())))) else {
    abort("completion shape mismatch")
  }
  let mut shards = 0L
  for x in 0..<((shape[0] - 1) / 8 + 1) {
    for y in 0..<((shape[1] - 1) / 32 + 1) {
      for z in 0..<((shape[2] - 1) / 32 + 1) {
        let key = "\{path}/c/\{x}/\{y}/\{z}"
        if !@sysfs.exists(key) ||
          @sysfs.kind(key, follow_symlink=false) != @sysfs.Regular {
          abort("missing output shard")
        }
        shards += 1L
      }
    }
  }
  if fields.get("shards") != Some(Json::number(shards.to_double())) {
    abort("completion shard count mismatch")
  }
  println("{\"status\":\"complete\",\"shards\":\{shards}}")
}

///|
async fn export_slice(
  path : String,
  index : String,
  destination : String,
) -> Unit {
  check_complete(path)
  let plane = dimension(index, false)
  guard @fs.FileStore::new(path) is Some(store) else { abort("input root") }
  guard store.open_f32("") is Some(array) else {
    abort("float32 array required")
  }
  let shape = array.metadata.shape
  guard shape.length() == 3 &&
    shape[1] <= 2048 &&
    shape[2] <= 2048 &&
    plane < shape[0] else {
    abort("3D slice required, plane at most 2048x2048")
  }
  guard array.read_region([plane, 0, 0], [1, shape[1], shape[2]])
    is Some(values) else {
    abort("slice read failed")
  }
  let rgba = Array::make(values.length() * 4, b'\xff')
  for i in 0..<values.length() {
    let value = values[i].to_double()
    if !(value >= 0.0 && value <= 1.0) {
      abort("normalized [0,1] values required")
    }
    let intensity = (value * 255.0 + 0.5).to_int().to_byte()
    rgba[i * 4] = intensity
    rgba[i * 4 + 1] = intensity
    rgba[i * 4 + 2] = intensity
  }
  let bytes = Bytes::from_array(rgba[:])
  let file = @sysfs.create(destination, allow_existing=false)
  defer file.close()
  file.write_at(bytes[:], position=0L)
  println(
    "{\"width\":\{shape[2]},\"height\":\{shape[1]},\"slice\":\{plane},\"rgba_bytes\":\{bytes.length()}}",
  )
}

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
  timings : Timings,
) -> @reader.Reader[Byte] {
  if source.has_prefix("https://") || source.has_prefix("http://") {
    guard @http.HttpStore::new(source) is Some(store) else {
      abort("HTTP source configuration")
    }
    return remote_reader(
      @remote.Source::http(store),
      path,
      origin,
      extent,
      timings,
    )
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
    return remote_reader(
      @remote.Source::s3(store),
      path,
      origin,
      extent,
      timings,
    )
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
  if args.length() == 3 && args[1] == "--check" {
    check_complete(args[2])
    return
  }
  if args.length() == 5 && args[1] == "--export-slice" {
    export_slice(args[2], args[3], args[4])
    return
  }
  if args.length() != 10 {
    abort("volume_pipeline INPUT ARRAY_PATH OUTPUT O0 O1 O2 N0 N1 N2")
  }
  let origin = Array::makei(3, i => dimension(args[4 + i], false))
  let extent = Array::makei(3, i => dimension(args[7 + i], true))
  let total_start = @metrics.time_ns()
  let timings = Timings::{ decode_ns: 0L, }
  let open_start = @metrics.time_ns()
  let reader = input_reader(args[1], args[2], origin, extent, timings)
  let open_ns = @metrics.time_ns() - open_start
  let first_start = @metrics.time_ns()
  let first = match reader.next() {
    Ok(Some(tile)) => tile
    _ => abort("first input tile failed; expected supported uint8 data")
  }
  let mut read_ns = @metrics.time_ns() - first_start
  let mut process_ns = 0L
  let write_start = @metrics.time_ns()
  // Exclusive directory creation prevents reuse of incomplete or unrelated
  // existing directories. Invalid initial input still creates no output.
  @sysfs.mkdir(args[3])
  guard @fs.FileStore::new(args[3]) is Some(output) else {
    abort("output root")
  }
  if !output.put(
      "pipeline-status.json", b"{\"schema_version\":1,\"status\":\"incomplete\"}",
    ) {
    abort("initial completion marker failed")
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
  let mut write_ns = @metrics.time_ns() - write_start
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
      None => {
        let read_start = @metrics.time_ns()
        let next = reader.next()
        read_ns += @metrics.time_ns() - read_start
        match next {
          Ok(Some(tile)) => tile
          Ok(None) => break
          Err(_) => abort("input tile failed; output is incomplete")
        }
      }
    }
    let process_start = @metrics.time_ns()
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
    process_ns += @metrics.time_ns() - process_start
    let shard_start = @metrics.time_ns()
    if !array.write_shard(coords, values) {
      abort("output shard failed; output is incomplete")
    }
    write_ns += @metrics.time_ns() - shard_start
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
  let final_start = @metrics.time_ns()
  if !output.put_attributes(@metadata.V3, "", attrs.stringify()) {
    abort("output provenance failed")
  }
  let shape_json = Json::array(extent.map(n => Json::number(n.to_double()))).stringify()
  let marker = "{\"schema_version\":1,\"status\":\"complete\",\"shape\":\{shape_json},\"voxels\":\{count},\"shards\":\{shard_count}}"
  if !output.put("pipeline-status.json", @utf8.encode(marker)) {
    abort("final completion marker failed")
  }
  write_ns += @metrics.time_ns() - final_start
  let total_ns = @metrics.time_ns() - total_start
  let decode_ns = timings.decode_ns
  let hydrate_ns = read_ns - decode_ns
  let rss = @metrics.peak_rss()
  let separated = args[1].has_prefix("http://") ||
    args[1].has_prefix("https://") ||
    args[1].has_prefix("s3://")
  let bins = histogram.map(n => n.to_string()).join(",")
  println(
    "{\"voxels\":\{count},\"input_checksum\":\{checksum},\"shards\":\{shard_count},\"histogram\":[\{bins}],\"completion\":\"complete\",\"timings\":{\"open_ns\":\{open_ns},\"hydrate_ns\":\{hydrate_ns},\"decode_ns\":\{decode_ns},\"process_ns\":\{process_ns},\"write_ns\":\{write_ns},\"total_ns\":\{total_ns},\"remote_decode_separated\":\{separated}},\"peak_rss_bytes\":\{rss}}",
  )
}
