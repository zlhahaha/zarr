///|
/// Read-only remote source; uses the existing transport budgets and cache.
pub struct Source {
  open : async (String) -> Result[@http.ArraySession, @store.AccessError]
}

///|
pub fn Source::http(store : @http.HttpStore) -> Source {
  { open: path => store.open_array_session_result(path), }
}

///|
pub fn Source::s3(store : @s3.S3Store) -> Source {
  { open: path => store.open_array_session_result(path), }
}

///|
/// Custom typed decoding supports every current dtype without collecting the
/// whole selection. Decode rejection is explicit and terminates this reader.
pub async fn[T] Source::open(
  self : Source,
  path : String,
  origin : Array[Int32],
  extent : Array[Int32],
  tile_shape : Array[Int32],
  decode : (@store.MemoryStore, String, @chunk.RegionTile) -> Array[T]?,
  max_tile_elements~ : Int32 = 8388608,
) -> Result[@reader.Reader[T], @store.AccessError] {
  let session = match (self.open)(path) {
    Err(error) => return Err(error)
    Ok(session) => session
  }
  let metadata = session.metadata()
  let read : async (@chunk.RegionTile) -> Result[Array[T], @store.AccessError] = tile => {
    let memory = match session.hydrate_region_result(tile.origin, tile.extent) {
      Err(error) => return Err(error)
      Ok(memory) => memory
    }
    match decode(memory, path, tile) {
      Some(values) => Ok(values)
      None => Err(@store.Protocol(path, "typed tile decode rejected"))
    }
  }
  match
    @reader.Reader::new(
      metadata.shape,
      origin,
      extent,
      tile_shape,
      read,
      max_tile_elements~,
    ) {
    Some(reader) => Ok(reader)
    None => Err(@store.InvalidRegion(path))
  }
}

///|
pub async fn Source::open_u8(
  self : Source,
  path : String,
  origin : Array[Int32],
  extent : Array[Int32],
  tile_shape : Array[Int32],
  max_tile_elements~ : Int32 = 8388608,
) -> Result[@reader.Reader[Byte], @store.AccessError] {
  self.open(
    path,
    origin,
    extent,
    tile_shape,
    (memory, path, tile) => {
      guard @array.open_u8(memory, path) is Some(array) else { return None }
      array.read_region(tile.origin, tile.extent).map(bytes => bytes.to_array())
    },
    max_tile_elements~,
  )
}

///|
pub async fn Source::open_u16(
  self : Source,
  path : String,
  origin : Array[Int32],
  extent : Array[Int32],
  tile_shape : Array[Int32],
  max_tile_elements~ : Int32 = 8388608,
) -> Result[@reader.Reader[UInt16], @store.AccessError] {
  self.open(
    path,
    origin,
    extent,
    tile_shape,
    (memory, path, tile) => {
      guard @array.open_u16(memory, path) is Some(array) else { return None }
      array.read_region(tile.origin, tile.extent)
    },
    max_tile_elements~,
  )
}

///|
pub async fn Source::open_f32(
  self : Source,
  path : String,
  origin : Array[Int32],
  extent : Array[Int32],
  tile_shape : Array[Int32],
  max_tile_elements~ : Int32 = 8388608,
) -> Result[@reader.Reader[Float], @store.AccessError] {
  self.open(
    path,
    origin,
    extent,
    tile_shape,
    (memory, path, tile) => {
      guard @array.open_f32(memory, path) is Some(array) else { return None }
      array.read_region(tile.origin, tile.extent)
    },
    max_tile_elements~,
  )
}
