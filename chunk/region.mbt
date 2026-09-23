///|
/// Validate a bounded N-dimensional rectangle and return its element count.
pub fn region_len(
  metadata : @metadata.ArrayMetadata,
  origin : Array[Int],
  extent : Array[Int],
) -> Int? {
  if origin.length() != metadata.shape.length() ||
    extent.length() != metadata.shape.length() {
    return None
  }
  let mut empty = false
  for i in 0..<origin.length() {
    let start = origin[i]
    let count = extent[i]
    let size = metadata.shape[i]
    if start < 0 || count < 0 || start > size || count > size - start {
      return None
    }
    if count == 0 {
      empty = true
    }
  }
  if empty {
    return Some(0)
  }
  let mut length = 1
  for count in extent {
    if length > 2147483647 / count {
      return None
    }
    length *= count
  }
  Some(length)
}

///|
/// Convert a C-order linear position within a validated region to indices.
/// Call only when every extent is positive or when the region is scalar.
pub fn region_coords(
  origin : Array[Int],
  extent : Array[Int],
  linear : Int,
) -> Array[Int] {
  let coords : Array[Int] = []
  for _ in 0..<origin.length() {
    coords.push(0)
  }
  let mut remainder = linear
  for reverse_i in 0..<origin.length() {
    let i = origin.length() - reverse_i - 1
    coords[i] = origin[i] + remainder % extent[i]
    remainder /= extent[i]
  }
  coords
}

///|
/// The overlap between a requested rectangle and one regular-grid chunk.
pub(all) struct ChunkRegion {
  coordinates : Array[Int]
  origin : Array[Int]
  extent : Array[Int]
} derive(Debug)

///|
/// Enumerate chunks touched by a validated rectangle in chunk-grid C order.
pub fn region_chunks(
  metadata : @metadata.ArrayMetadata,
  origin : Array[Int],
  extent : Array[Int],
) -> Array[ChunkRegion]? {
  guard region_len(metadata, origin, extent) is Some(length) else {
    return None
  }
  let result : Array[ChunkRegion] = []
  if length == 0 {
    return Some(result)
  }
  let starts : Array[Int] = []
  let counts : Array[Int] = []
  let mut total = 1
  for i in 0..<origin.length() {
    let side = metadata.chunk_shape[i]
    if side <= 0 {
      return None
    }
    let first = origin[i] / side
    let last = (origin[i] + extent[i] - 1) / side
    let count = last - first + 1
    if total > 2147483647 / count {
      return None
    }
    total *= count
    starts.push(first)
    counts.push(count)
  }
  for linear in 0..<total {
    let coordinates : Array[Int] = []
    for _ in 0..<origin.length() {
      coordinates.push(0)
    }
    let mut remainder = linear
    for reverse_i in 0..<origin.length() {
      let i = origin.length() - reverse_i - 1
      coordinates[i] = starts[i] + remainder % counts[i]
      remainder /= counts[i]
    }
    let overlap_origin : Array[Int] = []
    let overlap_extent : Array[Int] = []
    for i in 0..<origin.length() {
      let chunk_start = coordinates[i] * metadata.chunk_shape[i]
      let chunk_end = if metadata.chunk_shape[i] >
        metadata.shape[i] - chunk_start {
        metadata.shape[i]
      } else {
        chunk_start + metadata.chunk_shape[i]
      }
      let start = if origin[i] > chunk_start { origin[i] } else { chunk_start }
      let requested_end = origin[i] + extent[i]
      let end = if requested_end < chunk_end {
        requested_end
      } else {
        chunk_end
      }
      overlap_origin.push(start)
      overlap_extent.push(end - start)
    }
    result.push({ coordinates, origin: overlap_origin, extent: overlap_extent })
  }
  Some(result)
}

///|
/// C-order offset of an element inside a previously validated rectangle.
pub fn region_index(
  origin : Array[Int],
  extent : Array[Int],
  indices : Array[Int],
) -> Int? {
  if origin.length() != extent.length() || origin.length() != indices.length() {
    return None
  }
  let mut offset = 0
  for i in 0..<origin.length() {
    if extent[i] <= 0 ||
      indices[i] < origin[i] ||
      indices[i] - origin[i] >= extent[i] {
      return None
    }
    if offset > (2147483647 - (indices[i] - origin[i])) / extent[i] {
      return None
    }
    offset = offset * extent[i] + indices[i] - origin[i]
  }
  Some(offset)
}
