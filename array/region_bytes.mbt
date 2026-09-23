///|
/// Copy a C-order region from encoded chunks, decoding each touched chunk
/// once. The element offset still follows the array's v2 C/F-order rules.
fn read_region_bytes(
  store : @store.MemoryStore,
  metadata : @metadata.ArrayMetadata,
  path : String,
  compression : @codec.Compression,
  chunk_bytes : Int,
  fill_element : Bytes,
  element_size : Int,
  origin : Array[Int],
  extent : Array[Int],
) -> Bytes? {
  if element_size <= 0 || fill_element.length() != element_size {
    return None
  }
  guard @chunk.region_len(metadata, origin, extent) is Some(length) else {
    return None
  }
  if length > 2147483647 / element_size {
    return None
  }
  guard @chunk.region_chunks(metadata, origin, extent) is Some(pieces) else {
    return None
  }
  let result = Bytes::make(length * element_size, b'\x00').to_array()
  for piece in pieces {
    guard @chunk.chunk_key(metadata, piece.coordinates, path) is Some(key) else {
      return None
    }
    let raw = match store.get(key) {
      None => None
      Some(encoded) =>
        match @codec.decode_chunk(compression, encoded, chunk_bytes) {
          Some(decoded) => Some(decoded)
          None => return None
        }
    }
    guard @chunk.region_len(metadata, piece.origin, piece.extent)
      is Some(piece_len) else {
      return None
    }
    for linear in 0..<piece_len {
      let indices = @chunk.region_coords(piece.origin, piece.extent, linear)
      guard @chunk.region_index(origin, extent, indices) is Some(output_index) else {
        return None
      }
      guard @chunk.element_location(metadata, indices, path)
        is Some((_, input_index)) else {
        return None
      }
      for byte_index in 0..<element_size {
        result[output_index * element_size + byte_index] = match raw {
          None => fill_element[byte_index]
          Some(decoded) => decoded[input_index * element_size + byte_index]
        }
      }
    }
  }
  Some(Bytes::from_array(result[:]))
}

///|
/// Modify and re-encode each touched chunk once. As with FileStore regions,
/// a later failure does not roll back chunks already written.
fn write_region_bytes(
  store : @store.MemoryStore,
  metadata : @metadata.ArrayMetadata,
  path : String,
  compression : @codec.Compression,
  chunk_bytes : Int,
  fill_element : Bytes,
  element_size : Int,
  origin : Array[Int],
  extent : Array[Int],
  values : Bytes,
) -> Bool {
  if element_size <= 0 || fill_element.length() != element_size {
    return false
  }
  guard @chunk.region_len(metadata, origin, extent) is Some(length) else {
    return false
  }
  if length > 2147483647 / element_size ||
    values.length() != length * element_size {
    return false
  }
  guard @chunk.region_chunks(metadata, origin, extent) is Some(pieces) else {
    return false
  }
  for piece in pieces {
    guard @chunk.chunk_key(metadata, piece.coordinates, path) is Some(key) else {
      return false
    }
    let raw = match store.get(key) {
      None => {
        let bytes = Bytes::make(chunk_bytes, b'\x00').to_array()
        for i in 0..<chunk_bytes {
          bytes[i] = fill_element[i % element_size]
        }
        Bytes::from_array(bytes[:])
      }
      Some(encoded) =>
        match @codec.decode_chunk(compression, encoded, chunk_bytes) {
          Some(decoded) => decoded
          None => return false
        }
    }
    let mutable = raw.to_array()
    guard @chunk.region_len(metadata, piece.origin, piece.extent)
      is Some(piece_len) else {
      return false
    }
    for linear in 0..<piece_len {
      let indices = @chunk.region_coords(piece.origin, piece.extent, linear)
      guard @chunk.region_index(origin, extent, indices) is Some(input_index) else {
        return false
      }
      guard @chunk.element_location(metadata, indices, path)
        is Some((_, output_index)) else {
        return false
      }
      for byte_index in 0..<element_size {
        mutable[output_index * element_size + byte_index] = values[input_index *
          element_size +
          byte_index]
      }
    }
    guard @codec.encode_chunk(compression, Bytes::from_array(mutable[:]))
      is Some(encoded) else {
      return false
    }
    store.put(key, encoded)
  }
  true
}
