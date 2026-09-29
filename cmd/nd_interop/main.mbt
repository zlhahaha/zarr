///|
/// Eight small writable N-D stores for independent Python verification.
/// Optional output root lets repeated runs preserve previous stores.
async fn main {
  let args = @env.args()
  if args.length() > 2 {
    abort("usage: nd_interop [OUTPUT_ROOT]")
  }
  let root = if args.length() == 2 { args[1] } else { "integration/.roundtrip" }
  for
    item in [
      ("nd3_v2_raw_u16", @metadata.V2, false, @codec.Raw),
      ("nd3_v3_zstd_u16", @metadata.V3, false, @codec.Zstd(3)),
      ("nd3_v3_gzip_be_u16", @metadata.V3, true, @codec.Gzip(1)),
      ("nd3_v2_f_gzip_be_u16", @metadata.V2, true, @codec.Gzip(1)),
    ] {
    let (name, format, big_endian, compression) = item
    guard @fs.FileStore::new("\{root}/\{name}.zarr") is Some(store) else {
      abort(name)
    }
    if name == "nd3_v2_f_gzip_be_u16" {
      if store.get(".zarray") is Some(_) || store.get("zarr.json") is Some(_) {
        abort("refusing to overwrite \{name}")
      }
      if !store.put_array_metadata(
          @metadata.V2,
          "",
          "{\"zarr_format\":2,\"shape\":[5,7,9],\"chunks\":[2,3,4],\"dtype\":\">u2\",\"order\":\"F\",\"fill_value\":60000,\"compressor\":{\"id\":\"gzip\",\"level\":1},\"filters\":null}",
        ) {
        abort(name)
      }
    } else {
      guard store.create_u16(
          format,
          "",
          [5, 7, 9],
          [2, 3, 4],
          (60000 : UInt16),
          big_endian~,
          compression~,
        )
        is Some(_) else {
        abort("create failed or store exists: \{name}")
      }
    }
    guard store.open_u16("") is Some(array) else { abort(name) }
    let values : Array[UInt16] = []
    for x in 1..<5 {
      for y in 1..<4 {
        for z in 1..<9 {
          values.push((1000 * x + 100 * y + z + 1).to_uint16())
        }
      }
    }
    if !array.write_region([1, 1, 1], [4, 3, 8], values) ||
      !array.write([4, 3, 8], (4316 : UInt16)) {
      abort(name)
    }
    guard @fs.FileStore::new("\{root}/\{name}.zarr") is Some(reopened) else {
      abort(name)
    }
    guard reopened.open_u16("") is Some(saved) else { abort(name) }
    guard saved.read_region([0, 0, 0], [5, 7, 9]) is Some(actual) else {
      abort(name)
    }
    for i in 0..<actual.length() {
      let p = @chunk.region_coords([0, 0, 0], [5, 7, 9], i)
      let expected = if p[0] >= 1 && p[1] >= 1 && p[1] < 4 && p[2] >= 1 {
        let bump = if p == [4, 3, 8] { 7 } else { 0 }
        (1000 * p[0] + 100 * p[1] + p[2] + 1 + bump).to_uint16()
      } else {
        (60000 : UInt16)
      }
      if actual[i] != expected {
        abort("\{name}: mismatch at linear index \{i}")
      }
    }
    println("verified MoonBit write/reopen: \{name}")
  }
  for
    item in [
      ("nd4_v2_gzip_f32", @metadata.V2, false, @codec.Gzip(1)),
      ("nd4_v3_raw_be_f32", @metadata.V3, true, @codec.Raw),
      ("nd4_v3_zstd_f32", @metadata.V3, false, @codec.Zstd(3)),
      ("nd4_v2_f_zlib_be_f32", @metadata.V2, true, @codec.Zlib(1)),
    ] {
    let (name, format, big_endian, compression) = item
    guard @fs.FileStore::new("\{root}/\{name}.zarr") is Some(store) else {
      abort(name)
    }
    if name == "nd4_v2_f_zlib_be_f32" {
      if store.get(".zarray") is Some(_) || store.get("zarr.json") is Some(_) {
        abort("refusing to overwrite \{name}")
      }
      if !store.put_array_metadata(
          @metadata.V2,
          "",
          "{\"zarr_format\":2,\"shape\":[3,5,7,4],\"chunks\":[2,2,3,3],\"dtype\":\">f4\",\"order\":\"F\",\"fill_value\":-1.5,\"compressor\":{\"id\":\"zlib\",\"level\":1},\"filters\":null}",
        ) {
        abort(name)
      }
    } else {
      guard store.create_f32(
          format,
          "",
          [3, 5, 7, 4],
          [2, 2, 3, 3],
          -1.5,
          big_endian~,
          compression~,
        )
        is Some(_) else {
        abort("create failed or store exists: \{name}")
      }
    }
    guard store.open_f32("") is Some(array) else { abort(name) }
    let values : Array[Float] = []
    for t in 1..<3 {
      for y in 1..<3 {
        for z in 1..<7 {
          for c in 1..<4 {
            values.push(
              Float::from_int(100 * t + 10 * y + z - 50) +
              Float::from_int(c) / 4.0,
            )
          }
        }
      }
    }
    if !array.write_region([1, 1, 1, 1], [2, 2, 6, 3], values) ||
      !array.write([2, 2, 6, 3], 183.75) {
      abort(name)
    }
    guard @fs.FileStore::new("\{root}/\{name}.zarr") is Some(reopened) else {
      abort(name)
    }
    guard reopened.open_f32("") is Some(saved) else { abort(name) }
    guard saved.read_region([0, 0, 0, 0], [3, 5, 7, 4]) is Some(actual) else {
      abort(name)
    }
    for i in 0..<actual.length() {
      let p = @chunk.region_coords([0, 0, 0, 0], [3, 5, 7, 4], i)
      let expected : Float = if p[0] >= 1 &&
        p[1] >= 1 &&
        p[1] < 3 &&
        p[2] >= 1 &&
        p[3] >= 1 {
        let bump = if p == [2, 2, 6, 3] { 7 } else { 0 }
        Float::from_int(100 * p[0] + 10 * p[1] + p[2] - 50 + bump) +
        Float::from_int(p[3]) / 4.0
      } else {
        -1.5
      }
      if actual[i] != expected {
        abort("\{name}: mismatch at linear index \{i}")
      }
    }
    println("verified MoonBit write/reopen: \{name}")
  }
}
