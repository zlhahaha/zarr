///|
fn dimensions_json(shape : Array[Int], positive : Bool) -> Json? {
  let values : Array[Json] = []
  for side in shape {
    if side < 0 || (positive && side == 0) {
      return None
    }
    values.push(Json::number(side.to_double()))
  }
  Some(Json::array(values))
}

///|
fn numeric_metadata_json(
  format : @metadata.Format,
  shape : Array[Int],
  chunk_shape : Array[Int],
  v2_dtype : String,
  v3_dtype : String,
  fill_value : Json,
  big_endian : Bool,
) -> String? {
  if shape.length() != chunk_shape.length() {
    return None
  }
  guard dimensions_json(shape, false) is Some(shape_json) else { return None }
  guard dimensions_json(chunk_shape, true) is Some(chunks_json) else {
    return None
  }
  let metadata = if format == @metadata.V2 {
    Json::object(
      Map([
        ("zarr_format", Json::number(2.0)),
        ("shape", shape_json),
        ("chunks", chunks_json),
        ("dtype", Json::string(v2_dtype)),
        ("compressor", Json::null()),
        ("fill_value", fill_value),
        ("order", Json::string("C")),
        ("filters", Json::null()),
      ]),
    )
  } else {
    let codec = if v3_dtype == "uint8" {
      Json::object(Map([("name", Json::string("bytes"))]))
    } else {
      Json::object(
        Map([
          ("name", Json::string("bytes")),
          (
            "configuration",
            Json::object(
              Map([
                (
                  "endian",
                  Json::string(if big_endian { "big" } else { "little" }),
                ),
              ]),
            ),
          ),
        ]),
      )
    }
    Json::object(
      Map([
        ("zarr_format", Json::number(3.0)),
        ("node_type", Json::string("array")),
        ("shape", shape_json),
        ("data_type", Json::string(v3_dtype)),
        (
          "chunk_grid",
          Json::object(
            Map([
              ("name", Json::string("regular")),
              (
                "configuration",
                Json::object(Map([("chunk_shape", chunks_json)])),
              ),
            ]),
          ),
        ),
        (
          "chunk_key_encoding",
          Json::object(
            Map([
              ("name", Json::string("default")),
              (
                "configuration",
                Json::object(Map([("separator", Json::string("/"))])),
              ),
            ]),
          ),
        ),
        ("fill_value", fill_value),
        ("codecs", Json::array([codec])),
      ]),
    )
  }
  Some(metadata.stringify())
}

///|
/// Build validated, uncompressed uint8 metadata for either Zarr format.
pub fn u8_metadata_json(
  format : @metadata.Format,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Byte,
) -> String? {
  numeric_metadata_json(
    format,
    shape,
    chunk_shape,
    "|u1",
    "uint8",
    Json::number(fill.to_int().to_double()),
    false,
  )
}

///|
/// Build validated, uncompressed float64 metadata. Non-finite fill values
/// need format-specific string encoding and are not supported yet.
pub fn f64_metadata_json(
  format : @metadata.Format,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Double,
  big_endian? : Bool = false,
) -> String? {
  if fill.is_nan() || fill.is_inf() {
    return None
  }
  numeric_metadata_json(
    format,
    shape,
    chunk_shape,
    if big_endian {
      ">f8"
    } else {
      "<f8"
    },
    "float64",
    Json::number(fill),
    big_endian,
  )
}

///|
pub fn f32_metadata_json(
  format : @metadata.Format,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Float,
  big_endian? : Bool = false,
) -> String? {
  if fill.is_nan() || fill.is_inf() {
    return None
  }
  numeric_metadata_json(
    format,
    shape,
    chunk_shape,
    if big_endian {
      ">f4"
    } else {
      "<f4"
    },
    "float32",
    Json::number(fill.to_double()),
    big_endian,
  )
}

///|
pub fn create_u8(
  store : @store.MemoryStore,
  format : @metadata.Format,
  path : String,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Byte,
) -> U8Array? {
  if node_exists(store, path) {
    return None
  }
  guard u8_metadata_json(format, shape, chunk_shape, fill) is Some(raw) else {
    return None
  }
  if !store.put_array_metadata(format, path, raw) {
    return None
  }
  open_u8(store, path)
}

///|
pub fn create_f64(
  store : @store.MemoryStore,
  format : @metadata.Format,
  path : String,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Double,
  big_endian? : Bool = false,
) -> F64Array? {
  if node_exists(store, path) {
    return None
  }
  guard f64_metadata_json(format, shape, chunk_shape, fill, big_endian~)
    is Some(raw) else {
    return None
  }
  if !store.put_array_metadata(format, path, raw) {
    return None
  }
  open_f64(store, path)
}

///|
pub fn create_f32(
  store : @store.MemoryStore,
  format : @metadata.Format,
  path : String,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Float,
  big_endian? : Bool = false,
) -> F32Array? {
  if node_exists(store, path) {
    return None
  }
  guard f32_metadata_json(format, shape, chunk_shape, fill, big_endian~)
    is Some(raw) else {
    return None
  }
  if !store.put_array_metadata(format, path, raw) {
    return None
  }
  open_f32(store, path)
}

///|
fn node_exists(store : @store.MemoryStore, path : String) -> Bool {
  for format in [@metadata.V2, @metadata.V3] {
    if @chunk.array_metadata_key(format, path) is Some(key) &&
      store.get(key) is Some(_) {
      return true
    }
    if @chunk.group_metadata_key(format, path) is Some(key) &&
      store.get(key) is Some(_) {
      return true
    }
  }
  false
}
