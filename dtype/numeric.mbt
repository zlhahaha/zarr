///|
pub fn u8_fill(value : Json) -> Byte? {
  guard value is Number(n, ..) else { return None }
  if n < 0.0 || n > 255.0 {
    return None
  }
  let i = n.to_int()
  if i.to_double() != n {
    return None
  }
  Some(i.to_byte())
}

///|
pub fn bool_fill(value : Json) -> Bool? {
  match value {
    True => Some(true)
    False => Some(false)
    _ => None
  }
}

///|
pub fn u16_fill(value : Json) -> UInt16? {
  guard value is Number(n, ..) else { return None }
  if n < 0.0 || n > 65535.0 {
    return None
  }
  let i = n.to_int()
  if i.to_double() != n {
    return None
  }
  Some(i.to_uint16())
}

///|
pub fn i16_fill(value : Json) -> Int16? {
  guard value is Number(n, ..) else { return None }
  if n < -32768.0 || n > 32767.0 {
    return None
  }
  let i = n.to_int()
  if i.to_double() != n {
    return None
  }
  Some(Int16::from_int(i))
}

///|
pub fn f64_fill(value : Json) -> Double? {
  match value {
    Number(n, ..) => Some(n)
    String("NaN") => Some(0x7FF8000000000000UL.reinterpret_as_double())
    String("Infinity") => Some(0x7FF0000000000000UL.reinterpret_as_double())
    String("-Infinity") => Some(0xFFF0000000000000UL.reinterpret_as_double())
    _ => None
  }
}

///|
pub fn f32_fill(value : Json) -> Float? {
  match value {
    Number(n, ..) => Some(Float::from_double(n))
    String("NaN") => Some(Float::reinterpret_from_uint(0x7FC00000U))
    String("Infinity") => Some(Float::reinterpret_from_uint(0x7F800000U))
    String("-Infinity") => Some(Float::reinterpret_from_uint(0xFF800000U))
    _ => None
  }
}

///|
pub fn i32_fill(value : Json) -> Int? {
  guard value is Number(n, ..) else { return None }
  if n < -2147483648.0 || n > 2147483647.0 {
    return None
  }
  let i = n.to_int()
  if i.to_double() != n {
    return None
  }
  Some(i)
}

///|
pub fn u32_fill(value : Json) -> UInt? {
  guard value is Number(n, ..) else { return None }
  if n < 0.0 || n > 4294967295.0 {
    return None
  }
  let i = n.to_uint()
  if i.to_double() != n {
    return None
  }
  Some(i)
}

///|
/// JSON numbers above 2^53 must use their preserved source representation.
/// Parsing a rounded Double would silently corrupt a 64-bit fill value.
pub fn i64_fill(value : Json) -> Int64? {
  guard value is Number(n, repr~) else { return None }
  match repr {
    Some(text) => {
      let parsed = @string.parse_int64(text, base=10) catch { _ => return None }
      Some(parsed)
    }
    None => {
      if n < -9007199254740992.0 || n > 9007199254740992.0 {
        return None
      }
      let parsed = n.to_int64()
      if parsed.to_double() == n {
        Some(parsed)
      } else {
        None
      }
    }
  }
}

///|
pub fn u64_fill(value : Json) -> UInt64? {
  guard value is Number(n, repr~) else { return None }
  match repr {
    Some(text) => {
      let parsed = @string.parse_uint64(text, base=10) catch {
        _ => return None
      }
      Some(parsed)
    }
    None => {
      if n < 0.0 || n > 9007199254740992.0 {
        return None
      }
      let parsed = n.to_uint64()
      if parsed.to_double() == n {
        Some(parsed)
      } else {
        None
      }
    }
  }
}

///|
pub fn is_u8(metadata : @metadata.ArrayMetadata) -> Bool {
  match metadata.format {
    @metadata.V2 => metadata.data_type == "|u1"
    @metadata.V3 => metadata.data_type == "uint8"
  }
}

///|
pub fn is_bool(metadata : @metadata.ArrayMetadata) -> Bool {
  match metadata.format {
    @metadata.V2 => metadata.data_type == "|b1"
    @metadata.V3 => metadata.data_type == "bool"
  }
}

///|
pub fn u16_endian(metadata : @metadata.ArrayMetadata) -> Bool? {
  match metadata.format {
    @metadata.V2 =>
      match metadata.data_type {
        "<u2" => Some(false)
        ">u2" => Some(true)
        _ => None
      }
    @metadata.V3 =>
      if metadata.data_type == "uint16" {
        Some(false)
      } else {
        None
      }
  }
}

///|
pub fn i16_endian(metadata : @metadata.ArrayMetadata) -> Bool? {
  match metadata.format {
    @metadata.V2 =>
      match metadata.data_type {
        "<i2" => Some(false)
        ">i2" => Some(true)
        _ => None
      }
    @metadata.V3 =>
      if metadata.data_type == "int16" {
        Some(false)
      } else {
        None
      }
  }
}

///|
/// Whether float64 is big-endian, if the dtype is supported.
pub fn f64_endian(metadata : @metadata.ArrayMetadata) -> Bool? {
  match metadata.format {
    @metadata.V2 =>
      match metadata.data_type {
        "<f8" => Some(false)
        ">f8" => Some(true)
        _ => None
      }
    @metadata.V3 =>
      if metadata.data_type == "float64" {
        Some(false)
      } else {
        None
      }
  }
}

///|
pub fn f32_endian(metadata : @metadata.ArrayMetadata) -> Bool? {
  match metadata.format {
    @metadata.V2 =>
      match metadata.data_type {
        "<f4" => Some(false)
        ">f4" => Some(true)
        _ => None
      }
    @metadata.V3 =>
      if metadata.data_type == "float32" {
        Some(false)
      } else {
        None
      }
  }
}

///|
pub fn i32_endian(metadata : @metadata.ArrayMetadata) -> Bool? {
  match metadata.format {
    @metadata.V2 =>
      match metadata.data_type {
        "<i4" => Some(false)
        ">i4" => Some(true)
        _ => None
      }
    @metadata.V3 =>
      if metadata.data_type == "int32" {
        Some(false)
      } else {
        None
      }
  }
}

///|
pub fn u32_endian(metadata : @metadata.ArrayMetadata) -> Bool? {
  match metadata.format {
    @metadata.V2 =>
      match metadata.data_type {
        "<u4" => Some(false)
        ">u4" => Some(true)
        _ => None
      }
    @metadata.V3 =>
      if metadata.data_type == "uint32" {
        Some(false)
      } else {
        None
      }
  }
}

///|
pub fn i64_endian(metadata : @metadata.ArrayMetadata) -> Bool? {
  match metadata.format {
    @metadata.V2 =>
      match metadata.data_type {
        "<i8" => Some(false)
        ">i8" => Some(true)
        _ => None
      }
    @metadata.V3 =>
      if metadata.data_type == "int64" {
        Some(false)
      } else {
        None
      }
  }
}

///|
pub fn u64_endian(metadata : @metadata.ArrayMetadata) -> Bool? {
  match metadata.format {
    @metadata.V2 =>
      match metadata.data_type {
        "<u8" => Some(false)
        ">u8" => Some(true)
        _ => None
      }
    @metadata.V3 =>
      if metadata.data_type == "uint64" {
        Some(false)
      } else {
        None
      }
  }
}
