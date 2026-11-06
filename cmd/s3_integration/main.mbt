///|
fn required_env(name : String) -> String {
  guard @env.get_env_var(name) is Some(value) else {
    abort("missing integration-test environment: \{name}")
  }
  value
}

///|
/// Invoked by scripts/verify_s3_minio.py with disposable test credentials.
async fn main {
  let scenario = required_env("ZARR_S3_CASE")
  guard @s3.Credentials::new(
      required_env("ZARR_S3_ACCESS_KEY"),
      required_env("ZARR_S3_SECRET_KEY"),
    )
    is Some(credentials) else {
    abort("invalid test credentials")
  }
  guard @s3.S3Store::new(
      required_env("ZARR_S3_BUCKET"),
      "us-east-1",
      endpoint=required_env("ZARR_S3_ENDPOINT"),
      prefix="dataset",
      credentials~,
      allow_insecure_http=true,
      request_timeout_ms=if scenario == "timeout" { 250 } else { 5000 },
    )
    is Some(remote) else {
    abort("invalid test endpoint")
  }
  if scenario == "denied" || scenario == "timeout" {
    if remote.open_array("ordinary") is Some(_) {
      abort("expected failed authenticated request")
    }
    println("S3 integration: \{scenario} rejected")
    return
  }
  guard remote.open_array("ordinary") is Some(metadata) else {
    abort("authenticated metadata read failed")
  }
  if metadata.shape != [3] {
    abort("ordinary shape")
  }
  if scenario == "retry" {
    println("S3 integration: transient retry succeeded")
    return
  }
  guard remote.hydrate_region("ordinary", [0], [3]) is Some(cache) else {
    abort("ordinary hydration")
  }
  guard @array.open_u8(cache, "ordinary") is Some(ordinary) else {
    abort("ordinary typed open")
  }
  if ordinary.read_region([0], [3]) != Some(b"\x05\x05\x09") {
    abort("ordinary gzip values or missing-chunk fill")
  }
  guard remote.hydrate_region("start", [0], [9]) is Some(cache) else {
    abort("start-index hydration")
  }
  guard @array.open_u8(cache, "start") is Some(start) else {
    abort("start-index typed open")
  }
  if start.read_region([0], [9]) !=
    Some(b"\x05\x0b\x05\x05\x05\x05\x16\x05\x21") {
    abort("start-index values")
  }
  guard remote.hydrate_region("end", [0, 0], [5, 7]) is Some(cache) else {
    abort("end-index hydration")
  }
  guard @array.open_u16(cache, "end") is Some(end) else {
    abort("end-index typed open")
  }
  guard end.read_region([0, 0], [5, 7]) is Some(values) else {
    abort("end-index decode")
  }
  for row in 0..<5 {
    for col in 0..<7 {
      let expected = if row < 3 && col >= 1 && col < 6 {
        100 + row * 5 + col - 1
      } else {
        7
      }
      if values[row * 7 + col].to_int() != expected {
        abort("end-index values")
      }
    }
  }
  guard remote.hydrate_region("missing-shard", [0], [9]) is Some(cache) else {
    abort("missing shard hydration")
  }
  guard @array.open_u8(cache, "missing-shard") is Some(missing) else {
    abort("missing shard typed open")
  }
  if missing.read_region([0], [9]) !=
    Some(b"\x05\x05\x05\x05\x05\x05\x05\x05\x05") {
    abort("missing shard fill")
  }
  if remote.open_array("missing-array") is Some(_) {
    abort("missing metadata must not open")
  }
  println(
    "S3 integration: ordinary gzip, start/end shards, all values and missing fills verified",
  )
}
