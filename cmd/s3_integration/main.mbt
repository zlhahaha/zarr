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
    match remote.open_array_result("ordinary") {
      Err(@store.Authentication(_, 403)) if scenario == "denied" => ()
      Err(@store.Timeout(_)) if scenario == "timeout" => ()
      _ => abort("expected precise authenticated request failure")
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
  guard @remote.Source::s3(remote).open_u8("start", [0], [9], [3]) is Ok(reader) else {
    abort("signed sharded tile reader")
  }
  let collected : Array[Byte] = []
  while true {
    match reader.next() {
      Ok(Some(tile)) =>
        for value in tile.values {
          collected.push(value)
        }
      Ok(None) => break
      Err(_) => abort("signed sharded tile decode")
    }
  }
  if Bytes::from_array(collected[:]) != b"\x05\x0b\x05\x05\x05\x05\x16\x05\x21" {
    abort("signed sharded tile values")
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
  guard @s3.S3Store::new(
      required_env("ZARR_S3_BUCKET"),
      "us-east-1",
      endpoint=required_env("ZARR_S3_ENDPOINT"),
      prefix="catalog",
      credentials~,
      allow_insecure_http=true,
      listing_page_size=2,
    )
    is Some(catalog) else {
    abort("catalog store")
  }
  let children = match catalog.list_children_result("") {
    Ok(nodes) => nodes
    Err(_) => abort("catalog listing failed")
  }
  if children.map(node => node.path) != ["end", "nested", "start", "μ & 图"] {
    for node in children {
      println("observed catalog child: \{node.path}")
    }
    abort("catalog children")
  }
  let nodes = match catalog.walk_result("") {
    Ok(nodes) => nodes
    Err(_) => abort("catalog traversal")
  }
  if nodes.map(node => node.path) !=
    ["end", "nested", "start", "μ & 图", "nested/cube"] {
    abort("catalog walk order")
  }
  if !(catalog.walk_result("", max_nodes=4) is Err(@store.LimitExceeded(_, _))) ||
    !(catalog.walk_result("", max_depth=1) is Err(@store.LimitExceeded(_, _))) ||
    !(catalog.list_children_result("start") is Err(@store.NotGroup("start"))) ||
    !(catalog.open_array_result("nested") is Err(@store.NotArray("nested"))) {
    abort("catalog limits and kinds")
  }
  guard @s3.S3Store::new(
      required_env("ZARR_S3_BUCKET"),
      "us-east-1",
      endpoint=required_env("ZARR_S3_ENDPOINT"),
      prefix="catalog",
      credentials~,
      allow_insecure_http=true,
      listing_page_size=2,
      max_listing_pages=1,
    )
    is Some(limited) else {
    abort("limited catalog")
  }
  if !(limited.list_children_result("")
    is Err(@store.LimitExceeded("listing pages", ""))) {
    abort("pagination budget")
  }
  guard catalog.hydrate_region_result("μ & 图", [0], [9]) is Ok(unicode_cache) else {
    abort("Unicode signed path")
  }
  guard @array.open_u8(unicode_cache, "μ & 图") is Some(unicode_array) else {
    abort("Unicode array")
  }
  if unicode_array.read_region([0], [9]) !=
    Some(b"\x05\x0b\x05\x05\x05\x05\x16\x05\x21") {
    abort("Unicode values")
  }
  println(
    "S3 integration: ordinary gzip, start/end shards, all values and missing fills verified",
  )
  println(
    "S3 discovery: signed pagination, Unicode paths, explicit groups and traversal limits verified",
  )
}
