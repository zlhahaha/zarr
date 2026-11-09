///|
/// Pack already-encoded inner chunks in C index order. None is the missing
/// fill sentinel. No codecs are applied here. The entire shard is buffered.
pub fn encode(
  layout : @metadata.Sharding,
  chunks : Array[Bytes?],
  max_bytes~ : Int32 = 67108864,
) -> Bytes? {
  if max_bytes <= 0 ||
    layout.chunks_per_shard.length() != layout.shard_shape.length() {
    return None
  }
  let mut count = 1
  for i in 0..<layout.chunks_per_shard.length() {
    let n = layout.chunks_per_shard[i]
    if n <= 0 ||
      layout.shard_shape[i] <= 0 ||
      layout.shard_shape[i] % n != 0 ||
      count > (16777216 - 4) / 16 / n {
      return None
    }
    count *= n
  }
  let index_size = count * 16 + (if layout.index_crc32c { 4 } else { 0 })
  if chunks.length() != count ||
    layout.index_size != index_size ||
    index_size > max_bytes {
    return None
  }
  let mut size = index_size
  for chunk in chunks {
    if chunk is Some(bytes) {
      if bytes.length() == 0 || bytes.length() > max_bytes - size {
        return None
      }
      size += bytes.length()
    }
  }
  let output = Array::make(size, b'\x00')
  let index = Array::make(index_size, b'\xff')
  let mut at = if layout.index_at_start { index_size } else { 0 }
  for i in 0..<count {
    if chunks[i] is Some(bytes) {
      for field in 0..<2 {
        let value = (if field == 0 { at } else { bytes.length() }).to_uint64()
        for b in 0..<8 {
          let shift = (if layout.index_big_endian { 7 - b } else { b }) * 8
          index[i * 16 + field * 8 + b] = ((value >> shift) & 255UL).to_byte()
        }
      }
      for j in 0..<bytes.length() {
        output[at + j] = bytes[j]
      }
      at += bytes.length()
    }
  }
  if layout.index_crc32c {
    let checksum = crc32c(Bytes::from_array(index[:index_size - 4])[:])
    for b in 0..<4 {
      index[index_size - 4 + b] = ((checksum >> (b * 8)) & 255U).to_byte()
    }
  }
  let index_at = if layout.index_at_start { 0 } else { at }
  for i in 0..<index_size {
    output[index_at + i] = index[i]
  }
  Some(Bytes::from_array(output[:]))
}

///|
/// Wrap an ordinary supported v3 inner-chunk document in sharding_indexed.
/// Shape/dtype/fill/attributes and the inner codec pipeline are preserved.
pub fn metadata_json(
  inner_raw : String,
  shard_shape : Array[Int32],
  index_at_start~ : Bool = false,
  index_big_endian~ : Bool = false,
  index_crc32c~ : Bool = true,
) -> String? {
  guard @metadata.parse_array_metadata(inner_raw) is Some(inner) else {
    return None
  }
  if inner.format != @metadata.V3 ||
    inner.sharding is Some(_) ||
    shard_shape.length() != inner.shape.length() {
    return None
  }
  guard (@json.parse(inner_raw) catch { _ => return None }) is Object(fields) else {
    return None
  }
  let dimensions = shard_shape.map(n => Json::number(n.to_double()))
  let inner_dimensions = inner.chunk_shape.map(n => Json::number(n.to_double()))
  fields["chunk_grid"] = Json::object(
    Map([
      ("name", Json::string("regular")),
      (
        "configuration",
        Json::object(Map([("chunk_shape", Json::array(dimensions))])),
      ),
    ]),
  )
  let index_codecs = [
    Json::object(
      Map([
        ("name", Json::string("bytes")),
        (
          "configuration",
          Json::object(
            Map([
              (
                "endian",
                Json::string(if index_big_endian { "big" } else { "little" }),
              ),
            ]),
          ),
        ),
      ]),
    ),
  ]
  if index_crc32c {
    index_codecs.push(Json::object(Map([("name", Json::string("crc32c"))])))
  }
  fields["codecs"] = Json::array([
    Json::object(
      Map([
        ("name", Json::string("sharding_indexed")),
        (
          "configuration",
          Json::object(
            Map([
              ("chunk_shape", Json::array(inner_dimensions)),
              ("codecs", Json::array(inner.codecs)),
              ("index_codecs", Json::array(index_codecs)),
              (
                "index_location",
                Json::string(if index_at_start { "start" } else { "end" }),
              ),
            ]),
          ),
        ),
      ]),
    ),
  ])
  let raw = Json::object(fields).stringify()
  guard @metadata.parse_array_metadata(raw) is Some(outer) else { return None }
  guard prepare(outer) is Some(prepared) else { return None }
  if prepared.sharding is None || prepared.chunk_shape != inner.chunk_shape {
    return None
  }
  Some(raw)
}
