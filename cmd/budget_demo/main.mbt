///|
async fn main {
  guard @store.ReadLimits::new(
      max_chunk_bytes=4,
      max_decoded_chunk_bytes=4,
      max_region_elements=4,
      max_chunks=2,
    )
    is Some(limits) else {
    abort("limits")
  }
  let dir = @async_fs.tmpdir(prefix="zarr-budget-demo")
  defer @async_fs.rmdir(dir, recursive=true)
  guard @fs.FileStore::new(dir, read_limits=limits) is Some(store) else {
    abort("store")
  }
  guard store.create_u8(@metadata.V3, "", [8], [4], b'\x07') is Some(array) else {
    abort("array")
  }
  if array.read_region([0], [4]) != Some(b"\x07\x07\x07\x07") {
    abort("fill")
  }
  if array.read_region([0], [8]) is Some(_) {
    abort("region budget")
  }
  if !store.put("c/0", b"oversized") {
    abort("fixture")
  }
  let mut rejected = false
  let value = array.read([0]) catch {
    @fs.ReadLimitExceeded(_) => {
      rejected = true
      None
    }
    error => raise error
  }
  if !rejected || value is Some(_) {
    abort("encoded budget")
  }
  println("Zarr budgets: valid read passed; region and encoded chunk rejected")
}
