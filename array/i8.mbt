///|
/// Signed 8-bit Zarr values are exposed as Int with a strict -128..127 range.
pub struct I8Array {
  bits : U8Array
}

///|
pub fn open_i8(store : @store.MemoryStore, path : String) -> I8Array? {
  guard store.open_array(path) is Some(metadata) else { return None }
  open_i8_from_metadata(store, metadata, path)
}

///|
pub fn open_i8_from_metadata(
  store : @store.MemoryStore,
  metadata : @metadata.ArrayMetadata,
  path : String,
) -> I8Array? {
  guard @dtype.is_i8(metadata) else { return None }
  guard open_u8_bits_from_metadata(store, metadata, path) is Some(bits) else {
    return None
  }
  Some({ bits, })
}

///|
fn signed_byte(value : Byte) -> Int {
  let bits = value.to_int()
  if bits < 128 {
    bits
  } else {
    bits - 256
  }
}

///|
pub fn I8Array::read(self : I8Array, indices : Array[Int]) -> Int? {
  match self.bits.read(indices) {
    Some(value) => Some(signed_byte(value))
    None => None
  }
}

///|
pub fn I8Array::write(
  self : I8Array,
  indices : Array[Int],
  value : Int,
) -> Bool {
  if value < -128 || value > 127 {
    return false
  }
  self.bits.write(indices, (value & 255).to_byte())
}

///|
pub fn I8Array::read_region(
  self : I8Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[Int]? {
  guard self.bits.read_region(origin, extent) is Some(bytes) else {
    return None
  }
  let values : Array[Int] = []
  for value in bytes {
    values.push(signed_byte(value))
  }
  Some(values)
}

///|
pub fn I8Array::write_region(
  self : I8Array,
  origin : Array[Int],
  extent : Array[Int],
  values : Array[Int],
) -> Bool {
  let bytes : Array[Byte] = []
  for value in values {
    if value < -128 || value > 127 {
      return false
    }
    bytes.push((value & 255).to_byte())
  }
  self.bits.write_region(origin, extent, Bytes::from_array(bytes[:]))
}
