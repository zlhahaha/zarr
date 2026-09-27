///|
fn codec_name(value : Json) -> String? {
  guard value is Object(fields) else { return None }
  guard fields.get("name") is Some(String(name)) else { return None }
  Some(name)
}

///|
fn codec_configuration(value : Json) -> Map[String, Json]? {
  guard value is Object(fields) else { return None }
  guard fields.get("configuration") is Some(Object(config)) else { return None }
  Some(config)
}

///|
fn positive_dimensions(value : Json, rank : Int) -> Array[Int]? {
  guard value is Array(values) else { return None }
  if values.length() != rank {
    return None
  }
  let result : Array[Int] = []
  for value in values {
    guard value is Number(n, ..) else { return None }
    if n < 1.0 || n > 2147483647.0 {
      return None
    }
    let side = n.to_int()
    if n != side.to_double() || side <= 0 {
      return None
    }
    result.push(side)
  }
  Some(result)
}

///|
/// Convert a supported sharding codec into an inner-chunk view. Unsupported
/// index and inner pipelines are rejected explicitly by this or typed openers.
pub fn prepare(metadata : @metadata.ArrayMetadata) -> @metadata.ArrayMetadata? {
  if metadata.format != @metadata.V3 ||
    metadata.codecs.length() != 1 ||
    codec_name(metadata.codecs[0]) != Some("sharding_indexed") {
    return Some(metadata)
  }
  if metadata.sharding is Some(_) || metadata.storage_transformers.length() != 0 {
    return None
  }
  guard codec_configuration(metadata.codecs[0]) is Some(config) else {
    return None
  }
  guard config.get("chunk_shape") is Some(inner_json) else { return None }
  guard positive_dimensions(inner_json, metadata.shape.length())
    is Some(inner_shape) else {
    return None
  }
  guard config.get("codecs") is Some(Array(inner_codecs)) else { return None }
  if inner_codecs.length() == 0 ||
    inner_codecs.length() > 2 ||
    codec_name(inner_codecs[0]) != Some("bytes") {
    return None
  }
  guard config.get("index_codecs") is Some(Array(index_codecs)) else {
    return None
  }
  if index_codecs.length() < 1 ||
    index_codecs.length() > 2 ||
    codec_name(index_codecs[0]) != Some("bytes") {
    return None
  }
  let index_big_endian = match codec_configuration(index_codecs[0]) {
    Some(index_config) =>
      match index_config.get("endian") {
        Some(String("little")) => false
        Some(String("big")) => true
        _ => return None
      }
    None => false
  }
  let index_crc32c = index_codecs.length() == 2
  if index_crc32c && codec_name(index_codecs[1]) != Some("crc32c") {
    return None
  }
  let index_at_start = match config.get("index_location") {
    None | Some(String("end")) => false
    Some(String("start")) => true
    _ => return None
  }
  let chunks_per_shard : Array[Int] = []
  let mut index_entries = 1
  for i in 0..<inner_shape.length() {
    let outer = metadata.chunk_shape[i]
    let inner = inner_shape[i]
    if outer % inner != 0 {
      return None
    }
    let count = outer / inner
    if count <= 0 || index_entries > (16777216 - 4) / 16 / count {
      return None
    }
    index_entries *= count
    chunks_per_shard.push(count)
  }
  let index_size = index_entries * 16 + (if index_crc32c { 4 } else { 0 })
  Some({
    format: metadata.format,
    shape: metadata.shape,
    chunk_shape: inner_shape,
    data_type: metadata.data_type,
    separator: metadata.separator,
    key_encoding: metadata.key_encoding,
    codecs: inner_codecs,
    v2_filter_count: metadata.v2_filter_count,
    storage_transformers: metadata.storage_transformers,
    fill_value: metadata.fill_value,
    order: metadata.order,
    sharding: Some({
      shard_shape: metadata.chunk_shape,
      chunks_per_shard,
      index_size,
      index_at_start,
      index_big_endian,
      index_crc32c,
    }),
  })
}

///|
/// Map an inner chunk coordinate to its outer shard and local index.
pub fn coordinates(
  metadata : @metadata.ArrayMetadata,
  inner : Array[Int],
) -> (Array[Int], Array[Int])? {
  guard metadata.sharding is Some(layout) else { return None }
  if inner.length() != layout.chunks_per_shard.length() {
    return None
  }
  let outer : Array[Int] = []
  let within : Array[Int] = []
  for i in 0..<inner.length() {
    if inner[i] < 0 {
      return None
    }
    let count = layout.chunks_per_shard[i]
    outer.push(inner[i] / count)
    within.push(inner[i] % count)
  }
  Some((outer, within))
}
