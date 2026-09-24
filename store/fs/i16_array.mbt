///|
/// Native filesystem view of a signed 16-bit Zarr array.
pub struct FileI16Array {
  bits : FileU16Array
}

///|
pub async fn FileStore::open_i16(
  self : FileStore,
  path : String,
) -> FileI16Array? {
  guard self.open_array(path) is Some(metadata) else { return None }
  let scratch = @store.MemoryStore::new()
  guard @array.open_i16_from_metadata(scratch, metadata, path) is Some(_) else {
    return None
  }
  Some({ bits: { store: self, metadata, path, }, })
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
pub async fn FileI16Array::read(
  self : FileI16Array,
  indices : Array[Int],
) -> Int16? {
  match self.bits.read(indices) {
    Some(value) => Some(bits_to_i16(value))
    None => None
  }
}

///|
pub async fn FileI16Array::write(
  self : FileI16Array,
  indices : Array[Int],
  value : Int16,
) -> Bool {
  self.bits.write(indices, i16_to_bits(value))
}

///|
pub async fn FileI16Array::read_region(
  self : FileI16Array,
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
pub async fn FileI16Array::write_region(
  self : FileI16Array,
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
