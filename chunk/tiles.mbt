///|
/// A bounded rectangle returned by RegionTileCursor. Tiles are C-ordered and
/// do not contain values; pass each origin/extent to a typed read_region.
#derive(Debug)
pub(all) struct RegionTile {
  origin : Array[Int32]
  extent : Array[Int32]
}

///|
pub extend RegionTile with Debug::{to_repr}

///|
/// Incremental N-dimensional tile planner. It never enumerates or allocates
/// the complete requested region, so even a region larger than Int.MAX can be
/// traversed when each individual tile is bounded.
pub struct RegionTileCursor {
  origin : Array[Int32]
  extent : Array[Int32]
  tile_shape : Array[Int32]
  position : Array[Int32]
  mut finished : Bool
}

///|
/// `shape`, `origin`, `extent` and `tile_shape` have the same rank. Empty
/// regions produce no tiles; a rank-zero scalar produces one scalar tile.
/// `max_tile_elements` bounds one yielded tile, not the entire traversal.
pub fn RegionTileCursor::new(
  shape : Array[Int32],
  origin : Array[Int32],
  extent : Array[Int32],
  tile_shape : Array[Int32],
  max_tile_elements~ : Int32 = 8388608,
) -> RegionTileCursor? {
  let rank = shape.length()
  if origin.length() != rank ||
    extent.length() != rank ||
    tile_shape.length() != rank ||
    max_tile_elements <= 0 {
    return None
  }
  let mut empty = false
  let mut tile_elements = 1
  for i in 0..<rank {
    if shape[i] < 0 ||
      origin[i] < 0 ||
      extent[i] < 0 ||
      origin[i] > shape[i] ||
      extent[i] > shape[i] - origin[i] ||
      tile_shape[i] <= 0 {
      return None
    }
    if extent[i] == 0 {
      empty = true
    }
    let side = if extent[i] < tile_shape[i] { extent[i] } else { tile_shape[i] }
    if side > 0 {
      if tile_elements > max_tile_elements / side {
        return None
      }
      tile_elements *= side
    }
  }
  Some({
    origin: origin.copy(),
    extent: extent.copy(),
    tile_shape: tile_shape.copy(),
    position: Array::make(rank, 0),
    finished: empty,
  })
}

///|
pub fn RegionTileCursor::next(self : RegionTileCursor) -> RegionTile? {
  if self.finished {
    return None
  }
  let rank = self.origin.length()
  let tile_origin : Array[Int32] = []
  let tile_extent : Array[Int32] = []
  for i in 0..<rank {
    let remaining = self.extent[i] - self.position[i]
    tile_origin.push(self.origin[i] + self.position[i])
    tile_extent.push(
      if remaining < self.tile_shape[i] {
        remaining
      } else {
        self.tile_shape[i]
      },
    )
  }
  if rank == 0 {
    self.finished = true
  } else {
    let mut carried = true
    for reverse_i in 0..<rank {
      let i = rank - reverse_i - 1
      if carried {
        let remaining = self.extent[i] - self.position[i]
        if self.tile_shape[i] < remaining {
          self.position[i] += self.tile_shape[i]
          carried = false
        } else {
          self.position[i] = 0
        }
      }
    }
    if carried {
      self.finished = true
    }
  }
  Some({ origin: tile_origin, extent: tile_extent, })
}
