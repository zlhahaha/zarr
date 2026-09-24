///|
/// Unsigned 32-bit Zarr array backed by the shared four-byte chunk engine.
pub struct U32Array {
  bits : I32Array
}

///|
pub fn open_u32(store : @store.MemoryStore, path : String) -> U32Array? {
  guard store.open_array(path) is Some(metadata) else { return None }
  open_u32_from_metadata(store, metadata, path)
}

///|
pub fn open_u32_from_metadata(
  store : @store.MemoryStore,
  metadata : @metadata.ArrayMetadata,
  path : String,
) -> U32Array? {
  guard @dtype.u32_endian(metadata) is Some(_) else { return None }
  guard open_i32_bits_from_metadata(store, metadata, path) is Some(bits) else {
    return None
  }
  Some({ bits, })
}

///|
pub fn U32Array::read(self : U32Array, indices : Array[Int]) -> UInt? {
  match self.bits.read(indices) {
    Some(value) => Some(value.reinterpret_as_uint())
    None => None
  }
}

///|
pub fn U32Array::write(
  self : U32Array,
  indices : Array[Int],
  value : UInt,
) -> Bool {
  self.bits.write(indices, value.reinterpret_as_int())
}

///|
pub fn U32Array::read_region(
  self : U32Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[UInt]? {
  guard self.bits.read_region(origin, extent) is Some(raw) else { return None }
  let result : Array[UInt] = []
  for value in raw {
    result.push(value.reinterpret_as_uint())
  }
  Some(result)
}

///|
pub fn U32Array::write_region(
  self : U32Array,
  origin : Array[Int],
  extent : Array[Int],
  values : Array[UInt],
) -> Bool {
  let raw : Array[Int] = []
  for value in values {
    raw.push(value.reinterpret_as_int())
  }
  self.bits.write_region(origin, extent, raw)
}
