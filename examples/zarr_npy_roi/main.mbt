///|
// NPY v1.0 header for this example's C-order uint8 patches.
fn npy_header(shape : Array[Int32]) -> Bytes {
  let dimensions = shape.map(side => side.to_string()).join(", ")
  let fields = "{'descr': '|u1', 'fortran_order': False, 'shape': (\{dimensions}), }"
  let text = @utf8.encode(fields)
  let preamble_len = 10
  let pad = (64 - (preamble_len + text.length() + 1) % 64) % 64
  let header_len = text.length() + pad + 1
  let header = b"\x93NUMPY\x01\x00".to_array()
  header.push(header_len.to_byte())
  header.push((header_len >> 8).to_byte())
  for byte in text {
    header.push(byte)
  }
  for _ in 0..<pad {
    header.push(b' ')
  }
  header.push(b'\n')
  Bytes::from_array(header[:])
}

///|
async fn main {
  let args = @env.args()
  let batch = args.length() == 4 && args[3] == "--batch"
  guard args.length() == 3 || batch else {
    abort("usage: zarr_npy_roi HTTP_ARRAY_ROOT NEW_OUTPUT.npy [--batch]")
  }
  // Cross the 64-voxel source chunk boundary on each of the three axes.
  let origin = [56, 56, 56]
  let shape = [16, 16, 16]
  let origins = if batch {
    [origin, [0, 0, 0], [8, 8, 8], [112, 112, 112]]
  } else {
    [origin]
  }
  guard @http.HttpStore::new(args[1]) is Some(remote) else {
    abort("invalid HTTP array URL")
  }
  guard remote.open_array_session_result("") is Ok(session) else {
    abort("could not open source Zarr metadata")
  }
  let patches = []
  for patch_origin in origins {
    guard session.hydrate_region_result(patch_origin, shape) is Ok(memory) &&
      @array.open_u8(memory, "") is Some(array) &&
      array.read_region(patch_origin, shape) is Some(values) else {
      abort("could not read a uint8 patch")
    }
    patches.push(values)
  }
  let header = npy_header(
    if batch {
      [origins.length(), ..shape]
    } else {
      shape
    },
  )
  let output = @fs.create(args[2], allow_existing=false)
  defer output.close()
  output.write_at(header[:], position=0L)
  let mut offset = header.length().to_int64()
  for values in patches {
    output.write_at(values[:], position=offset)
    offset += values.length().to_int64()
  }
  println(
    Json::array(
      origins.map(point => {
        Json::array(point.map(axis => Json::number(axis.to_double())))
      }),
    ).stringify(),
  )
}
