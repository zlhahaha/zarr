///|
/// Small in-memory uint8 example. The filesystem backend and codecs are
/// separate future work.
fn main {
  let store = @zarr.MemoryStore::new()
  let metadata =
    #|{"zarr_format":3,"node_type":"array","shape":[4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  if !store.put_array_metadata(@zarr.V3, "samples", metadata) {
    println("metadata rejected")
    return
  }
  guard store.open_u8("samples") is Some(array) else {
    println("array not found")
    return
  }
  if !array.write_region([1], [3], b"\x07\x09\x0b") {
    println("write rejected")
    return
  }
  guard array.read_region([0], [4]) is Some(bytes) else {
    println("read rejected")
    return
  }
  println(
    "Zarr v3 uint8 values: \{bytes[0].to_int()},\{bytes[1].to_int()},\{bytes[2].to_int()},\{bytes[3].to_int()}",
  )
}
