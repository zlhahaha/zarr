///|
fn box_strides(shape : Array[Int], fortran : Bool) -> Array[Int]? {
  let strides = Array::make(shape.length(), 0)
  let mut size = 1
  for step in 0..<shape.length() {
    let axis = if fortran { step } else { shape.length() - step - 1 }
    let count = shape[axis]
    if count <= 0 || size > 2147483647 / count {
      return None
    }
    strides[axis] = size
    size *= count
  }
  Some(strides)
}

///|
/// Visit last-axis runs of an overlap, mapping a C/F-order source box to a
/// C-order destination box. The callback receives source/destination element
/// offsets, run length and source stride. All geometry is validated before
/// calling it; invalid/overflowing geometry returns false, empty overlap true.
/// Scratch space is O(rank), not O(elements). This low-level geometry helper
/// does not allocate/copy buffers or enforce ReadLimits; callers own both.
/// Do not mutate the supplied geometry arrays from inside the callback.
pub fn copy_region_spans(
  source_origin : Array[Int],
  source_shape : Array[Int],
  destination_origin : Array[Int],
  destination_shape : Array[Int],
  overlap_origin : Array[Int],
  overlap_shape : Array[Int],
  copy : (Int, Int, Int, Int) -> Unit,
  source_fortran? : Bool = false,
) -> Bool {
  let rank = overlap_shape.length()
  if source_origin.length() != rank ||
    source_shape.length() != rank ||
    destination_origin.length() != rank ||
    destination_shape.length() != rank ||
    overlap_origin.length() != rank {
    return false
  }
  let mut empty = false
  for axis in 0..<rank {
    let start = overlap_origin[axis]
    let count = overlap_shape[axis]
    if source_origin[axis] < 0 ||
      destination_origin[axis] < 0 ||
      count < 0 ||
      source_shape[axis] < 0 ||
      destination_shape[axis] < 0 ||
      start < source_origin[axis] ||
      start < destination_origin[axis] {
      return false
    }
    let source_offset = start - source_origin[axis]
    let destination_offset = start - destination_origin[axis]
    if source_offset > source_shape[axis] ||
      destination_offset > destination_shape[axis] ||
      count > source_shape[axis] - source_offset ||
      count > destination_shape[axis] - destination_offset {
      return false
    }
    if count == 0 {
      empty = true
    }
  }
  if empty {
    return true
  }
  guard box_strides(source_shape, source_fortran) is Some(source_strides) else {
    return false
  }
  guard box_strides(destination_shape, false) is Some(destination_strides) else {
    return false
  }
  if rank == 0 {
    copy(0, 0, 1, 1)
    return true
  }
  let mut source = 0
  let mut destination = 0
  let mut rows = 1
  for axis in 0..<rank {
    source += (overlap_origin[axis] - source_origin[axis]) *
      source_strides[axis]
    destination += (overlap_origin[axis] - destination_origin[axis]) *
      destination_strides[axis]
    if axis < rank - 1 {
      rows *= overlap_shape[axis]
    }
  }
  let positions = Array::make(rank - 1, 0)
  for row in 0..<rows {
    copy(source, destination, overlap_shape[rank - 1], source_strides[rank - 1])
    if row + 1 < rows {
      for step in 0..<(rank - 1) {
        let axis = rank - step - 2
        if positions[axis] + 1 < overlap_shape[axis] {
          positions[axis] += 1
          source += source_strides[axis]
          destination += destination_strides[axis]
          break
        } else {
          source -= positions[axis] * source_strides[axis]
          destination -= positions[axis] * destination_strides[axis]
          positions[axis] = 0
        }
      }
    }
  }
  true
}
