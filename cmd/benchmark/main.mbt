///|
extern "C" fn time_ns() -> Int64 = "zarr_bench_time_ns"

///|
extern "C" fn peak_rss() -> Int64 = "zarr_bench_peak_rss"

///|
fn integer(value : String) -> Int {
  let parsed = @json.parse(value) catch { _ => abort("integer argument") }
  guard parsed is Number(n, ..) else { abort("integer argument") }
  if n < 0.0 || n > 16384.0 || n != n.to_int().to_double() {
    abort("integer out of range")
  }
  n.to_int()
}

///|
async fn main {
  let args = @env.args()
  if args.length() != 6 {
    abort("usage: benchmark STORE ROW COLUMN SIDE CACHE_MODE")
  }
  let row = integer(args[2])
  let column = integer(args[3])
  let side = integer(args[4])
  if side == 0 || (args[5] != "on" && args[5] != "off") {
    abort("invalid side/cache mode")
  }
  guard @fs.FileStore::new(
      args[1],
      shard_index_cache_bytes=if args[5] == "off" { 0 } else { 16777216 },
    )
    is Some(store) else {
    abort("store")
  }
  guard store.open_u16("") is Some(array) else { abort("open uint16") }
  let start = time_ns()
  guard array.read_region([row, column], [side, side]) is Some(values) else {
    abort("read region")
  }
  let elapsed = time_ns() - start
  if values.length() != side * side {
    abort("result length")
  }
  let mut checksum = 0L
  for r in 0..<side {
    for c in 0..<side {
      let expected = (((row + r) * 17 + (column + c) * 31) % 65521 + 1).to_uint16()
      let value = values[r * side + c]
      if value != expected {
        abort("benchmark value mismatch")
      }
      checksum += value.to_int().to_int64()
    }
  }
  let memory = peak_rss()
  let stats = store.shard_read_stats()
  if start < 0L || elapsed <= 0L || memory <= 0L {
    abort("OS metrics unavailable")
  }
  println(
    "{\"read_ns\":\{elapsed},\"peak_rss_bytes\":\{memory},\"checksum\":\{checksum},\"result_bytes\":\{side * side * 2},\"index_reads\":\{stats.index_reads},\"index_bytes\":\{stats.index_bytes},\"index_cache_hits\":\{stats.index_cache_hits},\"payload_reads\":\{stats.payload_reads},\"payload_bytes\":\{stats.payload_bytes},\"peak_cached_index_bytes\":\{stats.peak_cached_index_bytes}}",
  )
}
