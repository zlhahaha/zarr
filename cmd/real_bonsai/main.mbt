///|
/// Public, real 3D OME-Zarr microscopy data; no credentials or large download.
async fn main {
  let args = @env.args()
  if args.length() > 2 || (args.length() == 2 && args[1] != "--volume") {
    abort("usage: real_bonsai [--volume]")
  }
  let volume = args.length() == 2
  guard @s3.S3Store::new(
      "ome-zarr-scivis",
      "us-east-1",
      prefix="v0.4/64x0/bonsai.ome.zarr",
    )
    is Some(remote) else {
    abort("S3 configuration")
  }
  guard remote.open_array("scale0/bonsai") is Some(metadata) else {
    abort("public OME-Zarr metadata unavailable")
  }
  if metadata.shape != [256, 256, 256] {
    abort("public OME-Zarr shape changed")
  }
  let extent = if volume { [128, 128, 128] } else { [8, 8, 8] }
  let tile_shape = if volume { [64, 64, 64] } else { [4, 4, 4] }
  guard @chunk.RegionTileCursor::new(
      metadata.shape,
      [0, 0, 0],
      extent,
      tile_shape,
      max_tile_elements=if volume { 262144 } else { 64 },
    )
    is Some(tiles) else {
    abort("tile planning failed")
  }
  let mut sum = 0L
  let mut count = 0
  let mut first = -1
  let mut tile_count = 0
  while tiles.next() is Some(tile) {
    guard remote.hydrate_region("scale0/bonsai", tile.origin, tile.extent)
      is Some(cache) else {
      abort("public OME-Zarr hydration failed")
    }
    guard @array.open_u8(cache, "scale0/bonsai") is Some(image) else {
      abort("public OME-Zarr uint8 metadata unsupported")
    }
    guard image.read_region(tile.origin, tile.extent) is Some(values) else {
      abort(
        "public OME-Zarr decode failed at \{tile.origin[0]},\{tile.origin[1]},\{tile.origin[2]}",
      )
    }
    if first < 0 {
      first = values[0].to_int()
    }
    for value in values {
      sum += value.to_int().to_int64()
      count += 1
    }
    tile_count += 1
  }
  if (!volume && (count != 512 || sum != 20736L || first != 40)) ||
    (
      volume &&
      (count != 2097152 || tile_count != 8 || sum != 24039966L || first != 40)
    ) {
    abort("public OME-Zarr checksum mismatch")
  }
  println(
    "OME-Zarr bonsai: \{tile_count} bounded tiles, \{count} real voxels, checksum=\{sum}, first=\{first}",
  )
}
