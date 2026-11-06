///|
/// Native filesystem view of an unsigned 32-bit Zarr array.
pub struct FileU32Array {
  bits : FileI32Array
}

///|
pub async fn FileStore::open_u32(
  self : FileStore,
  path : String,
) -> FileU32Array? {
  guard self.open_array(path) is Some(metadata) else { return None }
  let scratch = self.scratch()
  guard @array.open_u32_from_metadata(scratch, metadata, path) is Some(_) else {
    return None
  }
  Some({ bits: { store: self, metadata, path, }, })
}

///|
pub async fn FileU32Array::read(
  self : FileU32Array,
  indices : Array[Int32],
) -> UInt32? {
  match self.bits.read(indices) {
    Some(value) => Some(value.reinterpret_as_uint())
    None => None
  }
}

///|
pub async fn FileU32Array::write(
  self : FileU32Array,
  indices : Array[Int32],
  value : UInt32,
) -> Bool {
  self.bits.write(indices, value.reinterpret_as_int())
}

///|
pub async fn FileU32Array::read_region(
  self : FileU32Array,
  origin : Array[Int32],
  extent : Array[Int32],
) -> Array[UInt32]? {
  guard self.bits.read_region(origin, extent) is Some(raw) else { return None }
  let result : Array[UInt32] = []
  for value in raw {
    result.push(value.reinterpret_as_uint())
  }
  Some(result)
}

///|
pub async fn FileU32Array::write_region(
  self : FileU32Array,
  origin : Array[Int32],
  extent : Array[Int32],
  values : Array[UInt32],
) -> Bool {
  let raw : Array[Int32] = []
  for value in values {
    raw.push(value.reinterpret_as_int())
  }
  self.bits.write_region(origin, extent, raw)
}
