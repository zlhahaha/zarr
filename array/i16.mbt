///|
/// Signed 16-bit Zarr array backed by the shared two-byte chunk engine.
pub struct I16Array {
  bits : U16Array
}

///|
pub fn open_i16(store : @store.MemoryStore, path : String) -> I16Array? {
  guard store.open_array(path) is Some(metadata) else { return None }
  open_i16_from_metadata(store, metadata, path)
}

///|
pub fn open_i16_from_metadata(
  store : @store.MemoryStore,
  metadata : @metadata.ArrayMetadata,
  path : String,
) -> I16Array? {
  guard @dtype.i16_endian(metadata) is Some(_) else { return None }
  guard open_u16_bits_from_metadata(store, metadata, path) is Some(bits) else {
    return None
  }
  Some({ bits, })
}

///|
fn i16_to_bits(value : Int16) -> UInt16 {
  (value.to_int() & 65535).to_uint16()
}

///|
fn bits_to_i16(value : UInt16) -> Int16 {
  let bits = value.to_int()
  Int16::from_int(if bits >= 32768 { bits - 65536 } else { bits })
}

///|
pub fn I16Array::read(self : I16Array, indices : Array[Int]) -> Int16? {
  match self.bits.read(indices) {
    Some(value) => Some(bits_to_i16(value))
    None => None
  }
}

///|
pub fn I16Array::write(
  self : I16Array,
  indices : Array[Int],
  value : Int16,
) -> Bool {
  self.bits.write(indices, i16_to_bits(value))
}

///|
pub fn I16Array::read_region(
  self : I16Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[Int16]? {
  guard self.bits.read_region(origin, extent) is Some(raw) else { return None }
  let result : Array[Int16] = []
  for value in raw {
    result.push(bits_to_i16(value))
  }
  Some(result)
}

///|
pub fn I16Array::write_region(
  self : I16Array,
  origin : Array[Int],
  extent : Array[Int],
  values : Array[Int16],
) -> Bool {
  let raw : Array[UInt16] = []
  for value in values {
    raw.push(i16_to_bits(value))
  }
  self.bits.write_region(origin, extent, raw)
}
