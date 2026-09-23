///|
/// Whether an array can be decoded as raw uncompressed uint8 bytes.
pub fn is_plain_u8(metadata : @metadata.ArrayMetadata) -> Bool {
  if metadata.storage_transformers.length() != 0 || !@dtype.is_u8(metadata) {
    return false
  }
  match metadata.format {
    @metadata.V2 => metadata.codecs.length() == 0
    @metadata.V3 => {
      if metadata.codecs.length() != 1 {
        return false
      }
      match metadata.codecs[0] {
        String("bytes") => true
        Object(map) => map.get("name") == Some(Json::string("bytes"))
        _ => false
      }
    }
  }
}

///|
/// Endianness of an uncompressed float64 array, or None for unsupported
/// codec chains. Multi-byte v3 values require an explicit bytes endian.
pub fn plain_f64_endian(metadata : @metadata.ArrayMetadata) -> Bool? {
  if metadata.storage_transformers.length() != 0 {
    return None
  }
  guard @dtype.f64_endian(metadata) is Some(v2_endian) else { return None }
  match metadata.format {
    @metadata.V2 =>
      if metadata.codecs.length() == 0 {
        Some(v2_endian)
      } else {
        None
      }
    @metadata.V3 => {
      if metadata.codecs.length() != 1 {
        return None
      }
      guard metadata.codecs[0] is Object(codec) else { return None }
      guard codec.get("name") == Some(Json::string("bytes")) else {
        return None
      }
      guard codec.get("configuration") is Some(Object(config)) else {
        return None
      }
      match config.get("endian") {
        Some(String("little")) => Some(false)
        Some(String("big")) => Some(true)
        _ => None
      }
    }
  }
}
