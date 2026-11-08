///|
fn positive(value : String) -> Int32 {
  let raw = @json.parse(value) catch { _ => abort("integer") }
  guard raw is Number(n, ..) else { abort("integer") }
  if n < 1.0 || n > 64.0 || n != n.to_int().to_double() {
    abort("range 1..64")
  }
  n.to_int()
}

///|
/// A fresh process per case; memory includes runtime/transport/decoder/result.
async fn main {
  let args = @env.args()
  if args.length() != 4 {
    abort("scan_benchmark BASE_URL TILE_SIDE PASSES")
  }
  let side = positive(args[2])
  let passes = positive(args[3])
  guard @http.HttpStore::new(args[1], max_cache_bytes=0) is Some(http) else {
    abort("http")
  }
  let source = @remote.Source::http(http)
  let histogram = Array::make(256, 0)
  let mut count = 0
  let mut sum = 0L
  let mut weighted = 0L
  let mut tiles = 0
  let start = @metrics.time_ns()
  for _ in 0..<passes {
    guard source.open_u8(
        "",
        [0, 0, 0],
        [128, 128, 128],
        [side, side, side],
        max_tile_elements=262144,
      )
      is Ok(reader) else {
      abort("open")
    }
    while true {
      let tile = match reader.next() {
        Ok(Some(tile)) => tile
        Ok(None) => break
        Err(_) => abort("read")
      }
      for i in 0..<tile.values.length() {
        let value = tile.values[i]
        let n = value.to_int()
        let z = tile.origin[2] + i % tile.extent[2]
        let y = tile.origin[1] + i / tile.extent[2] % tile.extent[1]
        let x = tile.origin[0] + i / (tile.extent[2] * tile.extent[1])
        weighted += ((x * 128 + y) * 128 + z + 1).to_int64() * n.to_int64()
        histogram[n] += 1
        sum += n.to_int64()
        count += 1
      }
      tiles += 1
    }
  }
  let elapsed = @metrics.time_ns() - start
  let rss = @metrics.peak_rss()
  if count != 2097152 * passes ||
    sum != 24039966L * passes.to_int64() ||
    elapsed <= 0L ||
    rss <= 0L {
    abort("checksum/metrics")
  }
  let hist = histogram.map(n => n.to_string()).join(",")
  println(
    "{\"elapsed_ns\":\{elapsed},\"peak_rss_bytes\":\{rss},\"passes\":\{passes},\"tile_side\":\{side},\"tiles\":\{tiles},\"voxels\":\{count},\"checksum\":\{sum},\"weighted_checksum\":\{weighted},\"histogram\":[\{hist}]}",
  )
}
