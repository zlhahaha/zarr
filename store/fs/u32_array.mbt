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
  let scratch = @store.MemoryStore::new()
  guard @array.open_u32_from_metadata(scratch, metadata, path) is Some(_) else {
    return None
  }
  Some({ bits: { store: self, metadata, path, }, })
}

///|
pub async fn FileU32Array::read(
  self : FileU32Array,
  indices : Array[Int],
) -> UInt? {
  match self.bits.read(indices) {
    Some(value) => Some(value.reinterpret_as_uint())
    None => None
  }
}

///|
pub async fn FileU32Array::write(
  self : FileU32Array,
  indices : Array[Int],
  value : UInt,
) -> Bool {
  self.bits.write(indices, value.reinterpret_as_int())
}

///|
pub async fn FileU32Array::read_region(
  self : FileU32Array,
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
pub async fn FileU32Array::write_region(
  self : FileU32Array,
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
