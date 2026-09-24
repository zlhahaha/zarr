///|
/// Unsigned 64-bit Zarr array backed by the shared eight-byte chunk engine.
pub struct U64Array {
  bits : I64Array
}

///|
pub fn open_u64(store : @store.MemoryStore, path : String) -> U64Array? {
  guard store.open_array(path) is Some(metadata) else { return None }
  open_u64_from_metadata(store, metadata, path)
}

///|
pub fn open_u64_from_metadata(
  store : @store.MemoryStore,
  metadata : @metadata.ArrayMetadata,
  path : String,
) -> U64Array? {
  guard @dtype.u64_endian(metadata) is Some(_) else { return None }
  guard open_i64_bits_from_metadata(store, metadata, path) is Some(bits) else {
    return None
  }
  Some({ bits, })
}

///|
pub fn U64Array::read(self : U64Array, indices : Array[Int]) -> UInt64? {
  match self.bits.read(indices) {
    Some(value) => Some(value.reinterpret_as_uint64())
    None => None
  }
}

///|
pub fn U64Array::write(
  self : U64Array,
  indices : Array[Int],
  value : UInt64,
) -> Bool {
  self.bits.write(indices, value.reinterpret_as_int64())
}

///|
pub fn U64Array::read_region(
  self : U64Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[UInt64]? {
  guard self.bits.read_region(origin, extent) is Some(raw) else { return None }
  let result : Array[UInt64] = []
  for value in raw {
    result.push(value.reinterpret_as_uint64())
  }
  Some(result)
}

///|
pub fn U64Array::write_region(
  self : U64Array,
  origin : Array[Int],
  extent : Array[Int],
  values : Array[UInt64],
) -> Bool {
  let raw : Array[Int64] = []
  for value in values {
    raw.push(value.reinterpret_as_int64())
  }
  self.bits.write_region(origin, extent, raw)
}
