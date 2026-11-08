///|
async fn check_array(
  directory : String,
  format : @metadata.Format,
  compression : @codec.Compression,
) -> Unit {
  guard @fs.FileStore::new(directory) is Some(store) else { abort("store") }
  guard store.create_u16(
      format,
      "",
      [3, 4, 5],
      [2, 3, 2],
      (60000 : UInt16),
      compression~,
    )
    is Some(array) else {
    abort("create")
  }
  let values : Array[UInt16] = []
  for i in 0..<12 {
    values.push((100 + i).to_uint16())
  }
  if !array.write_region([1, 1, 1], [2, 2, 3], values) {
    abort("write")
  }
  guard @fs.FileStore::new(directory) is Some(reopened) else {
    abort("reopen store")
  }
  guard reopened.open_u16("") is Some(saved) else { abort("open") }
  guard saved.read_region([0, 0, 0], [3, 4, 5]) is Some(all) else {
    abort("read")
  }
  for i in 0..<3 {
    for j in 0..<4 {
      for k in 0..<5 {
        let expected = if i >= 1 && j >= 1 && j < 3 && k >= 1 && k < 4 {
          100 + ((i - 1) * 2 + j - 1) * 3 + k - 1
        } else {
          60000
        }
        if all[(i * 4 + j) * 5 + k].to_int() != expected {
          abort("values")
        }
      }
    }
  }
  guard reopened.open_node_result("") is Ok(node) else {
    abort("published node API")
  }
  if node.kind != @hierarchy.ArrayNode || node.format != format {
    abort("node descriptor")
  }
  if !(reopened.list_children_result("") is Err(@store.NotGroup(""))) {
    abort("node kind error")
  }
  guard @reader.Reader::new([3, 4, 5], [0, 0, 0], [3, 4, 5], [2, 3, 2], tile => {
      match saved.read_region(tile.origin, tile.extent) {
        Some(values) => Ok(values)
        None => Err(@store.InvalidRegion("published"))
      }
    })
    is Some(reader) else {
    abort("published async reader")
  }
  let mut visited = 0
  while true {
    let tile = match reader.next() {
      Ok(Some(tile)) => tile
      Ok(None) => break
      Err(_) => abort("published scan")
    }
    for index in 0..<tile.values.length() {
      let k = tile.origin[2] + index % tile.extent[2]
      let j = tile.origin[1] + index / tile.extent[2] % tile.extent[1]
      let i = tile.origin[0] + index / (tile.extent[1] * tile.extent[2])
      if tile.values[index] != all[(i * 4 + j) * 5 + k] {
        abort("published scan coordinates")
      }
      visited += 1
    }
  }
  if visited != 60 {
    abort("published scan count")
  }
}

///|
async fn main {
  let args = @env.args()
  if args.length() != 2 {
    abort("usage: published_consumer OUTPUT_DIRECTORY")
  }
  check_array("\{args[1]}/v2", @metadata.V2, @codec.Gzip(1))
  check_array("\{args[1]}/v3", @metadata.V3, @codec.Zstd(3))
  guard @fs.FileStore::new("\{args[1]}/groups") is Some(groups) else {
    abort("group store")
  }
  if !groups.create_group_tree(@metadata.V3, "a") {
    abort("groups")
  }
  guard groups.create_u8(@metadata.V3, "b", [1], [1], b'\x07') is Some(_) else {
    abort("group array")
  }
  let nodes = match groups.walk_result("") {
    Ok(nodes) => nodes
    Err(_) => abort("published traversal")
  }
  if nodes.map(node => node.path) != ["a", "b"] {
    abort("published children")
  }
  if !(groups.walk_result("", max_nodes=1) is Err(@store.LimitExceeded(_, _))) {
    abort("published walk budget")
  }
  guard @s3.S3Store::new("bucket", "us-east-1", listing_page_size=2)
    is Some(remote) else {
    abort("published S3")
  }
  if !(remote.open_array_result("../blocked") is Err(@store.InvalidPath(_))) ||
    !(remote.hydrate_region_result("../blocked", [], [])
    is Err(@store.InvalidPath(_))) ||
    !(remote.list_children_result("../blocked") is Err(@store.InvalidPath(_))) {
    abort("published remote diagnostics")
  }
  println(
    "published Zarr: v2/v3 compressed 3D writes, reopen, all values and missing fills verified",
  )
  println("published discovery and structured errors verified")
  guard @scan.Reader::new([3], [0], [3], [1], tile => Ok([tile.origin[0]]))
    is Some(portable) else {
    abort("published portable reader")
  }
  guard portable.next() is Ok(Some(first)) else {
    abort("published portable tile")
  }
  if first.values != [0] {
    abort("published portable values")
  }
  portable.close()
  if !(portable.next() is Ok(None)) {
    abort("published early close")
  }
  if !(@scan_remote.Source::s3(remote).open_u8("../blocked", [], [], [])
    is Err(@store.InvalidPath(_))) {
    abort("published automatic source")
  }
  println(
    "published portable/native typed scans, early close and automatic source verified",
  )
}
