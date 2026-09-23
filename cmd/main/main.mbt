///|
/// Small in-memory uint8 example using the typed creation API.
fn main {
  let store = @store.MemoryStore::new()
  guard @array.create_u8(store, @metadata.V3, "samples", [4], [2], b'\x00')
    is Some(array) else {
    println("array creation rejected")
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
