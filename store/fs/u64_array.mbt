///|
/// Native filesystem view of an unsigned 64-bit Zarr array.
pub struct FileU64Array {
  bits : FileI64Array
}

///|
pub async fn FileStore::open_u64(
  self : FileStore,
  path : String,
) -> FileU64Array? {
  guard self.open_array(path) is Some(metadata) else { return None }
  let scratch = @store.MemoryStore::new()
  guard @array.open_u64_from_metadata(scratch, metadata, path) is Some(_) else {
    return None
  }
  Some({ bits: { store: self, metadata, path, }, })
}

///|
pub async fn FileU64Array::read(
  self : FileU64Array,
  indices : Array[Int],
) -> UInt64? {
  match self.bits.read(indices) {
    Some(value) => Some(value.reinterpret_as_uint64())
    None => None
  }
}

///|
pub async fn FileU64Array::write(
  self : FileU64Array,
  indices : Array[Int],
  value : UInt64,
) -> Bool {
  self.bits.write(indices, value.reinterpret_as_int64())
}

///|
pub async fn FileU64Array::read_region(
  self : FileU64Array,
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
pub async fn FileU64Array::write_region(
  self : FileU64Array,
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
