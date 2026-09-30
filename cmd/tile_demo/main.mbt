///|
fn main {
  let store = @store.MemoryStore::new()
  guard @array.create_u8(
      store,
      @metadata.V3,
      "large",
      [16384, 16384],
      [1024, 1024],
      b'\x01',
    )
    is Some(image) else {
    abort("large array metadata")
  }
  // The logical selection is 256 MiB, above the default 64 MiB read budget.
  if image.read_region([0, 0], [16384, 16384]) is Some(_) {
    abort("whole-region limit was not enforced")
  }
  guard @chunk.RegionTileCursor::new(
      [16384, 16384],
      [0, 0],
      [16384, 16384],
      [1024, 1024],
      max_tile_elements=1048576,
    )
    is Some(tiles) else {
    abort("tile plan")
  }
  let mut count = 0
  let mut sum = 0L
  let mut tile_count = 0
  while tiles.next() is Some(tile) {
    guard image.read_region(tile.origin, tile.extent) is Some(values) else {
      abort("bounded tile read")
    }
    if values.length() != 1048576 {
      abort("tile shape")
    }
    for value in values {
      sum += value.to_int().to_int64()
      count += 1
    }
    tile_count += 1
  }
  if count != 268435456 || sum != 268435456L || tile_count != 256 {
    abort("tiled scan checksum")
  }
  println("Zarr tiled scan: 256 MiB logical array, 256 tiles, checksum=\{sum}")
}
