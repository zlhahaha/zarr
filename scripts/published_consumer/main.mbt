///|
async fn check_array(
  directory : String,
  format : @metadata.Format,
  compression : @codec.Compression,
) -> Unit {
  guard @fs.FileStore::new(directory) is Some(store) else { abort("store") }
  guard store.create_u16(
      format,
      "",
      [3, 4, 5],
      [2, 3, 2],
      (60000 : UInt16),
      compression~,
    )
    is Some(array) else {
    abort("create")
  }
  let values : Array[UInt16] = []
  for i in 0..<12 {
    values.push((100 + i).to_uint16())
  }
  if !array.write_region([1, 1, 1], [2, 2, 3], values) {
    abort("write")
  }
  guard @fs.FileStore::new(directory) is Some(reopened) else {
    abort("reopen store")
  }
  guard reopened.open_u16("") is Some(saved) else { abort("open") }
  guard saved.read_region([0, 0, 0], [3, 4, 5]) is Some(all) else {
    abort("read")
  }
  for i in 0..<3 {
    for j in 0..<4 {
      for k in 0..<5 {
        let expected = if i >= 1 && j >= 1 && j < 3 && k >= 1 && k < 4 {
          100 + ((i - 1) * 2 + j - 1) * 3 + k - 1
        } else {
          60000
        }
        if all[(i * 4 + j) * 5 + k].to_int() != expected {
          abort("values")
        }
      }
    }
  }
}

///|
async fn main {
  let args = @env.args()
  if args.length() != 2 {
    abort("usage: published_consumer OUTPUT_DIRECTORY")
  }
  check_array("\{args[1]}/v2", @metadata.V2, @codec.Gzip(1))
  check_array("\{args[1]}/v3", @metadata.V3, @codec.Zstd(3))
  println(
    "published zarr 0.7.0: v2/v3 compressed 3D writes, reopen, all values and missing fills verified",
  )
}
