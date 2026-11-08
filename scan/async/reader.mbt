///|
/// Sequential async pull reader for filesystem or remote typed tiles.
/// No prefetch, total-result buffer, or implicit retry of a failed tile.
pub struct Reader[T] {
  cursor : @chunk.RegionTileCursor
  mut read : (async (@chunk.RegionTile) -> Result[Array[T], @store.AccessError])?
  mut failure : @store.AccessError?
  mut busy : Bool
  mut closed : Bool
}

///|
pub fn[T] Reader::new(
  shape : Array[Int32],
  origin : Array[Int32],
  extent : Array[Int32],
  tile_shape : Array[Int32],
  read : async (@chunk.RegionTile) -> Result[Array[T], @store.AccessError],
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
  Some({ cursor, read: Some(read), failure: None, busy: false, closed: false, })
}

///|
/// Only one next call may be in flight. Exceptions/cancellation propagate and
/// permanently close the reader; ordinary Result failures are sticky.
pub async fn[T] Reader::next(
  self : Reader[T],
) -> Result[@scan.Tile[T]?, @store.AccessError] {
  if self.busy {
    return Err(@store.Protocol("tile", "concurrent next"))
  }
  if self.failure is Some(error) {
    return Err(error)
  }
  guard self.read is Some(read) else { return Ok(None) }
  guard self.cursor.next() is Some(tile) else {
    self.close()
    return Ok(None)
  }
  let origin = tile.origin.copy()
  let extent = tile.extent.copy()
  self.busy = true
  // On unwind the callback stays detached. close during a call prevents reuse.
  self.read = None
  self.failure = Some(@store.Io("tile callback aborted"))
  defer {
    self.busy = false
  }
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
        let output : @scan.Tile[T] = { origin, extent, values, }
        Ok(Some(output))
      }
    }
  }
  if result is Err(error) {
    self.failure = Some(error)
  } else {
    self.failure = None
    if !self.closed {
      self.read = Some(read)
    }
  }
  result
}

///|
/// Close between next calls. It does not cancel an in-flight operation.
pub fn[T] Reader::close(self : Reader[T]) -> Unit {
  self.read = None
  self.closed = true
}
