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
  compression : @codec.Compression,
) -> String? {
  if shape.length() != chunk_shape.length() {
    return None
  }
  guard dimensions_json(shape, false) is Some(shape_json) else { return None }
  guard dimensions_json(chunk_shape, true) is Some(chunks_json) else {
    return None
  }
  let compressor_json = match compression {
    @codec.Raw => Json::null()
    @codec.Gzip(level) =>
      Json::object(
        Map([
          ("id", Json::string("gzip")),
          ("level", Json::number(level.to_double())),
        ]),
      )
    @codec.Zlib(level) =>
      Json::object(
        Map([
          ("id", Json::string("zlib")),
          ("level", Json::number(level.to_double())),
        ]),
      )
    @codec.Zstd(level) =>
      Json::object(
        Map([
          ("id", Json::string("zstd")),
          ("level", Json::number(level.to_double())),
        ]),
      )
  }
  let v3_compressor_json = match compression {
    @codec.Raw => None
    @codec.Gzip(level) =>
      Some(
        Json::object(
          Map([
            ("name", Json::string("gzip")),
            (
              "configuration",
              Json::object(Map([("level", Json::number(level.to_double()))])),
            ),
          ]),
        ),
      )
    @codec.Zstd(level) =>
      Some(
        Json::object(
          Map([
            ("name", Json::string("zstd")),
            (
              "configuration",
              Json::object(
                Map([
                  ("level", Json::number(level.to_double())),
                  ("checksum", Json::boolean(false)),
                ]),
              ),
            ),
          ]),
        ),
      )
    @codec.Zlib(_) => if format == @metadata.V2 { None } else { return None }
  }
  match compression {
    @codec.Gzip(level) | @codec.Zlib(level) if level < 0 || level > 9 =>
      return None
    @codec.Zstd(level) if level < 0 || level > 22 => return None
    _ => ()
  }
  let metadata = if format == @metadata.V2 {
    Json::object(
      Map([
        ("zarr_format", Json::number(2.0)),
        ("shape", shape_json),
        ("chunks", chunks_json),
        ("dtype", Json::string(v2_dtype)),
        ("compressor", compressor_json),
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
    let codecs = [codec]
    match v3_compressor_json {
      Some(value) => codecs.push(value)
      None => ()
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
        ("codecs", Json::array(codecs)),
      ]),
    )
  }
  Some(metadata.stringify())
}

///|
/// Build validated uint8 metadata for either Zarr format.
pub fn u8_metadata_json(
  format : @metadata.Format,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Byte,
  compression? : @codec.Compression = @codec.Raw,
) -> String? {
  numeric_metadata_json(
    format,
    shape,
    chunk_shape,
    "|u1",
    "uint8",
    Json::number(fill.to_int().to_double()),
    false,
    compression,
  )
}

///|
pub fn u16_metadata_json(
  format : @metadata.Format,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : UInt16,
  big_endian? : Bool = false,
  compression? : @codec.Compression = @codec.Raw,
) -> String? {
  numeric_metadata_json(
    format,
    shape,
    chunk_shape,
    if big_endian {
      ">u2"
    } else {
      "<u2"
    },
    "uint16",
    Json::number(fill.to_int().to_double()),
    big_endian,
    compression,
  )
}

///|
/// Build validated float64 metadata. Non-finite fill values
/// need format-specific string encoding and are not supported yet.
pub fn f64_metadata_json(
  format : @metadata.Format,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Double,
  big_endian? : Bool = false,
  compression? : @codec.Compression = @codec.Raw,
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
    compression,
  )
}

///|
pub fn f32_metadata_json(
  format : @metadata.Format,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Float,
  big_endian? : Bool = false,
  compression? : @codec.Compression = @codec.Raw,
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
    compression,
  )
}

///|
pub fn i32_metadata_json(
  format : @metadata.Format,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Int,
  big_endian? : Bool = false,
  compression? : @codec.Compression = @codec.Raw,
) -> String? {
  numeric_metadata_json(
    format,
    shape,
    chunk_shape,
    if big_endian {
      ">i4"
    } else {
      "<i4"
    },
    "int32",
    Json::number(fill.to_double()),
    big_endian,
    compression,
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
  compression? : @codec.Compression = @codec.Raw,
) -> U8Array? {
  if node_exists(store, path) {
    return None
  }
  guard u8_metadata_json(format, shape, chunk_shape, fill, compression~)
    is Some(raw) else {
    return None
  }
  if !store.put_array_metadata(format, path, raw) {
    return None
  }
  open_u8(store, path)
}

///|
pub fn create_u16(
  store : @store.MemoryStore,
  format : @metadata.Format,
  path : String,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : UInt16,
  big_endian? : Bool = false,
  compression? : @codec.Compression = @codec.Raw,
) -> U16Array? {
  if node_exists(store, path) {
    return None
  }
  guard u16_metadata_json(
      format,
      shape,
      chunk_shape,
      fill,
      big_endian~,
      compression~,
    )
    is Some(raw) else {
    return None
  }
  if !store.put_array_metadata(format, path, raw) {
    return None
  }
  open_u16(store, path)
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
  compression? : @codec.Compression = @codec.Raw,
) -> F64Array? {
  if node_exists(store, path) {
    return None
  }
  guard f64_metadata_json(
      format,
      shape,
      chunk_shape,
      fill,
      big_endian~,
      compression~,
    )
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
  compression? : @codec.Compression = @codec.Raw,
) -> F32Array? {
  if node_exists(store, path) {
    return None
  }
  guard f32_metadata_json(
      format,
      shape,
      chunk_shape,
      fill,
      big_endian~,
      compression~,
    )
    is Some(raw) else {
    return None
  }
  if !store.put_array_metadata(format, path, raw) {
    return None
  }
  open_f32(store, path)
}

///|
pub fn create_i32(
  store : @store.MemoryStore,
  format : @metadata.Format,
  path : String,
  shape : Array[Int],
  chunk_shape : Array[Int],
  fill : Int,
  big_endian? : Bool = false,
  compression? : @codec.Compression = @codec.Raw,
) -> I32Array? {
  if node_exists(store, path) {
    return None
  }
  guard i32_metadata_json(
      format,
      shape,
      chunk_shape,
      fill,
      big_endian~,
      compression~,
    )
    is Some(raw) else {
    return None
  }
  if !store.put_array_metadata(format, path, raw) {
    return None
  }
  open_i32(store, path)
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
