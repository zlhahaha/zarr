///|
fn dimension(raw : String) -> Int32 {
  let parsed = @json.parse(raw) catch { _ => abort("dimension") }
  guard parsed is Number(n, ..) &&
    n > 0.0 &&
    n <= 2048.0 &&
    n == n.to_int().to_double() else {
    abort("dimension 1..2048")
  }
  n.to_int()
}

///|
/// The volume application exports checked normalized float32 slices as RGBA.
/// Separate modules isolate incompatible async versions; no Python conversion.
async fn main {
  let args = @env.args()
  if args.length() != 5 {
    abort("zarr_preview INPUT_RGBA WIDTH HEIGHT NEW_PNG")
  }
  let width = dimension(args[2])
  let height = dimension(args[3])
  let input = @sysfs.open(args[1], mode=@sysfs.ReadOnly)
  defer input.close()
  let length = width * height * 4
  if input.size() != length.to_int64() {
    abort("RGBA byte length mismatch")
  }
  let rgba = input.read_exactly_at(length, position=0L)
  let png = @image.encode_png(@image.ImageData::{ width, height, data: rgba, })
  let output = @sysfs.create(args[4], allow_existing=false)
  defer output.close()
  output.write_at(png[:], position=0L)
  println(
    "{\"width\":\{width},\"height\":\{height},\"png_bytes\":\{png.length()}}",
  )
}
