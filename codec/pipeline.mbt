///|
/// Compression is applied after the bytes serializer. Zarr v2 names the
/// compressor separately; v3 lists it after the bytes codec.
pub(all) enum Compression {
  Raw
  Gzip(Int)
  Zlib(Int)
  Zstd(Int)
  ZstdChecksum(Int)
  BloscReadOnly(String)
} derive(Debug)

///|
pub extend Compression with Debug::{to_repr}

///|
fn level(value : Json?, default : Int, minimum : Int, maximum : Int) -> Int? {
  match value {
    None => Some(default)
    Some(Number(n, ..)) => {
      let integer = n.to_int()
      if n == integer.to_double() && integer >= minimum && integer <= maximum {
        Some(integer)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
fn compressor(codec : Json, v3 : Bool) -> Compression? {
  guard codec is Object(map) else { return None }
  let name = map.get(if v3 { "name" } else { "id" })
  let configured_level = if v3 {
    match map.get("configuration") {
      None => None
      Some(Object(config)) => config.get("level")
      _ => return None
    }
  } else {
    map.get("level")
  }
  match name {
    Some(String("gzip")) =>
      match level(configured_level, 6, 0, 9) {
        Some(value) => Some(Gzip(value))
        None => None
      }
    Some(String("zlib")) if !v3 =>
      match level(configured_level, 6, 0, 9) {
        Some(value) => Some(Zlib(value))
        None => None
      }
    Some(String("zstd")) => {
      let checksum = if v3 {
        guard map.get("configuration") is Some(Object(config)) else {
          return None
        }
        match config.get("checksum") {
          None | Some(False) => false
          Some(True) => true
          _ => return None
        }
      } else {
        false
      }
      match level(configured_level, 3, 0, 22) {
        Some(value) =>
          Some(if checksum { ZstdChecksum(value) } else { Zstd(value) })
        None => None
      }
    }
    Some(String("blosc")) => {
      let config = if v3 {
        guard map.get("configuration") is Some(Object(config)) else {
          return None
        }
        config
      } else {
        map
      }
      guard config.get("cname") is Some(String(cname)) else { return None }
      if cname != "lz4" &&
        cname != "lz4hc" &&
        cname != "zlib" &&
        cname != "zstd" {
        return None
      }
      let shuffle = config.get("shuffle")
      let shuffle_ok = if v3 {
        shuffle == Some(Json::string("noshuffle")) ||
        shuffle == Some(Json::string("shuffle"))
      } else {
        shuffle == Some(Json::number(0.0)) || shuffle == Some(Json::number(1.0))
      }
      if !shuffle_ok || level(config.get("clevel"), 5, 0, 9) is None {
        return None
      }
      Some(BloscReadOnly(cname))
    }
    _ => None
  }
}

///|
fn compression(metadata : @metadata.ArrayMetadata) -> Compression? {
  if metadata.storage_transformers.length() != 0 {
    return None
  }
  if metadata.v2_filter_count != 0 {
    return None
  }
  match metadata.format {
    @metadata.V2 =>
      match metadata.codecs.length() {
        0 => Some(Raw)
        1 => compressor(metadata.codecs[0], false)
        _ => None // v2 filters are not supported.
      }
    @metadata.V3 =>
      match metadata.codecs.length() {
        1 => Some(Raw)
        2 => compressor(metadata.codecs[1], true)
        _ => None
      }
  }
}

///|
pub fn u8_compression(metadata : @metadata.ArrayMetadata) -> Compression? {
  guard @dtype.is_u8(metadata) else { return None }
  byte_compression(metadata)
}

///|
pub fn i8_compression(metadata : @metadata.ArrayMetadata) -> Compression? {
  guard @dtype.is_i8(metadata) else { return None }
  byte_compression(metadata)
}

///|
fn byte_compression(metadata : @metadata.ArrayMetadata) -> Compression? {
  guard compression(metadata) is Some(plan) else { return None }
  match metadata.format {
    @metadata.V2 => Some(plan)
    @metadata.V3 =>
      match metadata.codecs[0] {
        String("bytes") => Some(plan)
        Object(map) if map.get("name") == Some(Json::string("bytes")) =>
          Some(plan)
        _ => None
      }
  }
}

///|
pub fn bool_compression(metadata : @metadata.ArrayMetadata) -> Compression? {
  guard @dtype.is_bool(metadata) else { return None }
  guard compression(metadata) is Some(plan) else { return None }
  match metadata.format {
    @metadata.V2 => Some(plan)
    @metadata.V3 =>
      match metadata.codecs[0] {
        String("bytes") => Some(plan)
        Object(map) if map.get("name") == Some(Json::string("bytes")) =>
          Some(plan)
        _ => None
      }
  }
}

///|
pub fn f32_plan(metadata : @metadata.ArrayMetadata) -> (Bool, Compression)? {
  guard @dtype.f32_endian(metadata) is Some(v2_endian) else { return None }
  numeric_plan(metadata, v2_endian)
}

///|
pub fn u16_plan(metadata : @metadata.ArrayMetadata) -> (Bool, Compression)? {
  guard @dtype.u16_endian(metadata) is Some(v2_endian) else { return None }
  numeric_plan(metadata, v2_endian)
}

///|
pub fn i16_plan(metadata : @metadata.ArrayMetadata) -> (Bool, Compression)? {
  guard @dtype.i16_endian(metadata) is Some(v2_endian) else { return None }
  numeric_plan(metadata, v2_endian)
}

///|
pub fn f64_plan(metadata : @metadata.ArrayMetadata) -> (Bool, Compression)? {
  guard @dtype.f64_endian(metadata) is Some(v2_endian) else { return None }
  numeric_plan(metadata, v2_endian)
}

///|
pub fn i32_plan(metadata : @metadata.ArrayMetadata) -> (Bool, Compression)? {
  guard @dtype.i32_endian(metadata) is Some(v2_endian) else { return None }
  numeric_plan(metadata, v2_endian)
}

///|
pub fn u32_plan(metadata : @metadata.ArrayMetadata) -> (Bool, Compression)? {
  guard @dtype.u32_endian(metadata) is Some(v2_endian) else { return None }
  numeric_plan(metadata, v2_endian)
}

///|
pub fn i64_plan(metadata : @metadata.ArrayMetadata) -> (Bool, Compression)? {
  guard @dtype.i64_endian(metadata) is Some(v2_endian) else { return None }
  numeric_plan(metadata, v2_endian)
}

///|
pub fn u64_plan(metadata : @metadata.ArrayMetadata) -> (Bool, Compression)? {
  guard @dtype.u64_endian(metadata) is Some(v2_endian) else { return None }
  numeric_plan(metadata, v2_endian)
}

///|
fn numeric_plan(
  metadata : @metadata.ArrayMetadata,
  v2_endian : Bool,
) -> (Bool, Compression)? {
  guard compression(metadata) is Some(plan) else { return None }
  match metadata.format {
    @metadata.V2 => Some((v2_endian, plan))
    @metadata.V3 => {
      guard metadata.codecs[0] is Object(codec) else { return None }
      guard codec.get("name") == Some(Json::string("bytes")) else {
        return None
      }
      guard codec.get("configuration") is Some(Object(config)) else {
        return None
      }
      match config.get("endian") {
        Some(String("little")) => Some((false, plan))
        Some(String("big")) => Some((true, plan))
        _ => None
      }
    }
  }
}

///|
pub fn decode_chunk(
  plan : Compression,
  encoded : Bytes,
  expected_len : Int,
) -> Bytes? {
  if expected_len < 0 {
    return None
  }
  match plan {
    Raw => if encoded.length() == expected_len { Some(encoded) } else { None }
    Gzip(_) => decode_gzip(encoded, expected_len)
    Zlib(_) => decode_zlib(encoded, expected_len)
    Zstd(_) => decode_zstd(encoded, expected_len)
    ZstdChecksum(_) =>
      if encoded.length() < 5 || (encoded[4].to_int() & 4) == 0 {
        None
      } else {
        decode_zstd(encoded, expected_len)
      }
    BloscReadOnly(cname) => decode_blosc(encoded, expected_len, cname)
  }
}

///|
fn decode_zstd(encoded : Bytes, expected_len : Int) -> Bytes? {
  let bound = @zstd.decompress_bound(encoded) catch { _ => return None }
  if bound > expected_len.to_uint64() {
    return None
  }
  let raw = @zstd.decompress(encoded) catch { _ => return None }
  if raw.length() == expected_len {
    Some(raw)
  } else {
    None
  }
}

///|
fn decode_gzip(encoded : Bytes, expected_len : Int) -> Bytes? {
  let decoder = @gzip.Decoder()
  let scratch = FixedArray::make(32768, b'\x00')
  let output : Array[Byte] = []
  let mut offset = 0
  for ;; {
    let status = decoder.step(encoded[offset:], scratch.mut_view(), end=true) catch {
      _ => return None
    }
    let consumed = decoder.last_consumed()
    let produced = decoder.last_produced()
    if produced > expected_len - output.length() {
      return None
    }
    output.append(scratch[:produced])
    offset = offset + consumed
    match status {
      @flate.Done => {
        if offset == encoded.length() &&
          decoder.unused_input().length() == 0 &&
          output.length() == expected_len {
          return Some(Bytes::from_array(output))
        }
        return None
      }
      @flate.NeedMoreInput | @flate.NeedMoreOutput =>
        if consumed == 0 && produced == 0 {
          return None
        }
    }
  }
}

///|
fn decode_zlib(encoded : Bytes, expected_len : Int) -> Bytes? {
  let decoder = @zlib.Decoder()
  let scratch = FixedArray::make(32768, b'\x00')
  let output : Array[Byte] = []
  let mut offset = 0
  for ;; {
    let status = decoder.step(encoded[offset:], scratch.mut_view(), end=true) catch {
      _ => return None
    }
    let consumed = decoder.last_consumed()
    let produced = decoder.last_produced()
    if produced > expected_len - output.length() {
      return None
    }
    output.append(scratch[:produced])
    offset = offset + consumed
    match status {
      @flate.Done => {
        if offset == encoded.length() &&
          decoder.unused_input().length() == 0 &&
          output.length() == expected_len {
          return Some(Bytes::from_array(output))
        }
        return None
      }
      @flate.NeedMoreInput | @flate.NeedMoreOutput =>
        if consumed == 0 && produced == 0 {
          return None
        }
    }
  }
}

///|
pub fn encode_chunk(plan : Compression, raw : Bytes) -> Bytes? {
  match plan {
    Raw => Some(raw)
    Gzip(level) => Some(@gzip.gzip_compress(raw, level~))
    Zlib(level) => Some(@zlib.zlib_compress(raw, level~))
    Zstd(level) => Some(@zstd.compress(raw, level~)) catch { _ => None }
    ZstdChecksum(level) =>
      Some(@zstd.compress(raw, level~, checksum=true)) catch {
        _ => None
      }
    BloscReadOnly(_) => None
  }
}
