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
pub fn f64_fill(value : Json) -> Double? {
  match value {
    Number(n, ..) => Some(n)
    _ => None
  }
}

///|
pub fn f32_fill(value : Json) -> Float? {
  match value {
    Number(n, ..) => Some(Float::from_double(n))
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
pub fn is_u8(metadata : @metadata.ArrayMetadata) -> Bool {
  match metadata.format {
    @metadata.V2 => metadata.data_type == "|u1"
    @metadata.V3 => metadata.data_type == "uint8"
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
