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
