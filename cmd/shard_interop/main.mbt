///|
async fn main {
  let args = @env.args()
  if args.length() != 2 && args.length() != 3 {
    abort("shard_interop OUTPUT_ROOT [verify]")
  }
  let root = args[1]
  if args.length() == 3 {
    if args[2] != "verify" {
      abort("verify argument")
    }
    guard @fs.FileStore::new("\{root}/u8-0.zarr") is Some(store) else {
      abort("store")
    }
    guard store.open_u8("") is Some(array) else { abort("open") }
    if array.read_region([0], [9]) !=
      Some(b"\x0b\x4d\x0d\x0e\x05\x05\x05\x05\x09") {
      abort("Python inner-chunk update")
    }
    guard @fs.FileStore::new("\{root}/u16.zarr") is Some(store) else {
      abort("store")
    }
    guard store.open_u16("") is Some(array) else { abort("open") }
    if array.read([4, 6]) != Some((65535 : UInt16)) {
      abort("Python uint16 edge update")
    }
    guard @fs.FileStore::new("\{root}/f32.zarr") is Some(store) else {
      abort("store")
    }
    guard store.open_f32("") is Some(array) else { abort("open") }
    if array.read([1, 3, 5]) != Some(-2.25F) {
      abort("Python float update")
    }
    println("MoonBit verified Python partial updates to MoonBit-written shards")
    return
  }
  for case in 0..<8 {
    guard @fs.FileStore::new("\{root}/u8-\{case}.zarr") is Some(store) else {
      abort("store")
    }
    guard store.create_sharded_u8(
        "",
        [9],
        [2],
        [4],
        b'\x05',
        compression=@codec.Gzip(1),
        index_at_start=(case & 1) != 0,
        index_big_endian=(case & 2) != 0,
        index_crc32c=(case & 4) != 0,
      )
      is Some(array) else {
      abort("create u8")
    }
    if !array.write_shard([0], b"\x01\x02\x03\x04") ||
      !array.write_shard([2], b"\x09") ||
      !array.write_shard([0], b"\x0b\x0c\x0d\x0e") {
      abort("write u8")
    }
    if array.read_region([0], [9]) !=
      Some(b"\x0b\x0c\x0d\x0e\x05\x05\x05\x05\x09") {
      abort("read u8")
    }
  }
  guard @fs.FileStore::new("\{root}/u16.zarr") is Some(store) else {
    abort("store")
  }
  guard store.create_sharded_u16(
      "",
      [5, 7],
      [2, 2],
      [4, 4],
      (7 : UInt16),
      compression=@codec.Zstd(3),
      big_endian=true,
      index_at_start=true,
      index_big_endian=true,
    )
    is Some(array) else {
    abort("create u16")
  }
  for row in 0..<2 {
    for column in 0..<2 {
      let rows = if row == 0 { 4 } else { 1 }
      let cols = if column == 0 { 4 } else { 3 }
      let values = Array::makei(rows * cols, i => {
        ((row * 4 + i / cols) * 100 + column * 4 + i % cols).to_uint16()
      })
      if !array.write_shard([row, column], values) {
        abort("write u16")
      }
    }
  }
  guard @fs.FileStore::new("\{root}/f32.zarr") is Some(store) else {
    abort("store")
  }
  guard store.create_sharded_f32(
      "",
      [3, 5, 7],
      [2, 2, 2],
      [2, 4, 4],
      -1.5F,
      compression=@codec.Gzip(1),
    )
    is Some(array) else {
    abort("create f32")
  }
  for a in 0..<2 {
    for b in 0..<2 {
      for c in 0..<2 {
        let d0 = if a == 0 { 2 } else { 1 }
        let d1 = if b == 0 { 4 } else { 1 }
        let d2 = if c == 0 { 4 } else { 3 }
        let values = Array::makei(d0 * d1 * d2, i => {
          let x = a * 2 + i / (d1 * d2)
          let y = b * 4 + i / d2 % d1
          let z = c * 4 + i % d2
          Float::from_int((x * 5 + y) * 7 + z) / 4.0 - 10.0
        })
        if !array.write_shard([a, b, c], values) {
          abort("write f32")
        }
      }
    }
  }
  println(
    "MoonBit wrote 10 sharded stores: all index layouts, gzip/zstd, edges and replacement",
  )
}
