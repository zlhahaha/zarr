///|
/// One C-ordered tile. The reader never retains yielded values.
pub(all) struct Tile[T] {
  origin : Array[Int32]
  extent : Array[Int32]
  values : Array[T]
}

///|
/// Pull-based synchronous reader, usable with any typed MemoryStore array.
/// A failed reader remains failed; close releases its source callback.
pub struct Reader[T] {
  cursor : @chunk.RegionTileCursor
  mut read : ((@chunk.RegionTile) -> Result[Array[T], @store.AccessError])?
  mut failure : @store.AccessError?
}

///|
pub fn[T] Reader::new(
  shape : Array[Int32],
  origin : Array[Int32],
  extent : Array[Int32],
  tile_shape : Array[Int32],
  read : (@chunk.RegionTile) -> Result[Array[T], @store.AccessError],
  max_tile_elements~ : Int32 = 8388608,
) -> Reader[T]? {
  guard @chunk.RegionTileCursor::new(
      shape,
      origin,
      extent,
      tile_shape,
      max_tile_elements~,
    )
    is Some(cursor) else {
    return None
  }
  Some({ cursor, read: Some(read), failure: None, })
}

///|
/// None means exhaustion or explicit close, never an I/O/decoding failure.
pub fn[T] Reader::next(
  self : Reader[T],
) -> Result[Tile[T]?, @store.AccessError] {
  if self.failure is Some(error) {
    return Err(error)
  }
  guard self.read is Some(read) else { return Ok(None) }
  guard self.cursor.next() is Some(tile) else {
    self.close()
    return Ok(None)
  }
  // Keep descriptor coordinates independent of an application callback.
  let origin = tile.origin.copy()
  let extent = tile.extent.copy()
  let result = match read(tile) {
    Err(error) => Err(error)
    Ok(values) => {
      let mut expected = 1
      for side in extent {
        expected *= side
      }
      if values.length() != expected {
        Err(@store.Protocol("tile", "decoded element count"))
      } else {
        Ok(Some({ origin, extent, values, }))
      }
    }
  }
  if result is Err(error) {
    self.failure = Some(error)
    self.read = None
  }
  result
}

///|
pub fn[T] Reader::close(self : Reader[T]) -> Unit {
  self.read = None
}
