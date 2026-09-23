///|
/// Small in-memory example. This exercises metadata and raw chunk storage,
/// not yet the codec pipeline or numeric array API.
fn main {
  let store = @zarr.MemoryStore::new()
  let metadata =
    #|{"zarr_format":3,"node_type":"array","shape":[4],"data_type":"uint8","chunk_grid":{"name":"regular","configuration":{"chunk_shape":[2]}},"chunk_key_encoding":{"name":"default"},"fill_value":0,"codecs":[{"name":"bytes"}]}
  if !store.put_array_metadata(@zarr.V3, "samples", metadata) {
    println("metadata rejected")
    return
  }
  guard store.open_array("samples") is Some(array) else {
    println("array not found")
    return
  }
  if !store.put_chunk(array, [0], "samples", b"\x07\x09") {
    println("chunk rejected")
    return
  }
  guard store.get_chunk(array, [0], "samples") is Some(bytes) else {
    println("chunk not found")
    return
  }
  println("Zarr v3 chunk samples/c/0: \{bytes.length()} bytes")
}
