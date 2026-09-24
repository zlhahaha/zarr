///|
/// Native filesystem view of a signed 8-bit Zarr array.
pub struct FileI8Array {
  bits : FileU8Array
}

///|
pub async fn FileStore::open_i8(
  self : FileStore,
  path : String,
) -> FileI8Array? {
  guard self.open_array(path) is Some(metadata) else { return None }
  let scratch = @store.MemoryStore::new()
  guard @array.open_i8_from_metadata(scratch, metadata, path) is Some(_) else {
    return None
  }
  Some({ bits: { store: self, metadata, path, }, })
}

///|
fn i8_value(value : Byte) -> Int {
  let bits = value.to_int()
  if bits < 128 {
    bits
  } else {
    bits - 256
  }
}

///|
pub async fn FileI8Array::read(
  self : FileI8Array,
  indices : Array[Int],
) -> Int? {
  match self.bits.read(indices) {
    Some(value) => Some(i8_value(value))
    None => None
  }
}

///|
pub async fn FileI8Array::write(
  self : FileI8Array,
  indices : Array[Int],
  value : Int,
) -> Bool {
  if value < -128 || value > 127 {
    return false
  }
  self.bits.write(indices, (value & 255).to_byte())
}

///|
pub async fn FileI8Array::read_region(
  self : FileI8Array,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[Int]? {
  guard self.bits.read_region(origin, extent) is Some(bytes) else {
    return None
  }
  let values : Array[Int] = []
  for value in bytes {
    values.push(i8_value(value))
  }
  Some(values)
}

///|
pub async fn FileI8Array::write_region(
  self : FileI8Array,
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
