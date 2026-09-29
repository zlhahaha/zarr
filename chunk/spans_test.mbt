///|
test "span mapping agrees with element indexing for rank zero through four and C/F order" {
  for rank in 0..<5 {
    for fortran in [false, true] {
      let source_origin = Array::make(rank, 1)
      let source_shape = Array::make(rank, 5)
      let destination_origin = Array::make(rank, 0)
      let destination_shape = Array::make(rank, 7)
      let overlap_origin = Array::make(rank, 2)
      let overlap_shape = Array::make(rank, 3)
      let mut count = 1
      for _ in 0..<rank {
        count *= 3
      }
      let actual : Array[(Int, Int)] = []
      assert_true(
        @chunk.copy_region_spans(
          source_origin,
          source_shape,
          destination_origin,
          destination_shape,
          overlap_origin,
          overlap_shape,
          fn(source, destination, length, stride) {
            for i in 0..<length {
              actual.push((source + i * stride, destination + i))
            }
          },
          source_fortran=fortran,
        ),
      )
      assert_eq(actual.length(), count)
      for linear in 0..<count {
        let coordinates = @chunk.region_coords(
          overlap_origin, overlap_shape, linear,
        )
        let mut source = 0
        let mut stride = 1
        for step in 0..<rank {
          let axis = if fortran { step } else { rank - step - 1 }
          source += (coordinates[axis] - source_origin[axis]) * stride
          stride *= source_shape[axis]
        }
        guard @chunk.region_index(
            destination_origin, destination_shape, coordinates,
          )
          is Some(destination) else {
          fail("reference destination")
        }
        assert_eq(actual[linear], (source, destination))
      }
    }
  }
}

///|
test "span validation is side effect free for invalid and overflowing boxes" {
  let mut calls = 0
  let visit = fn(_a, _b, _c, _d) { calls += 1 }
  assert_true(!@chunk.copy_region_spans([0], [3], [0], [3], [2], [2], visit))
  assert_true(!@chunk.copy_region_spans([0], [3], [0], [3], [-1], [1], visit))
  assert_true(!@chunk.copy_region_spans([0], [3], [], [], [0], [1], visit))
  assert_true(
    !@chunk.copy_region_spans(
      [0, 0],
      [2147483647, 2],
      [0, 0],
      [1, 1],
      [0, 0],
      [1, 1],
      visit,
    ),
  )
  assert_true(!@chunk.copy_region_spans([0], [3], [0], [3], [0], [-1], visit))
  assert_true(@chunk.copy_region_spans([0], [3], [0], [3], [3], [0], visit))
  assert_eq(calls, 0)
}

///|
test "asymmetric offset boxes and thin runs agree with a coordinate reference" {
  for seed in 0..<24 {
    let rank = seed % 4 + 1
    let source_origin = Array::make(rank, 1)
    let source_shape = Array::make(rank, 0)
    let destination_origin = Array::make(rank, 0)
    let destination_shape = Array::make(rank, 0)
    let overlap_origin = Array::make(rank, 0)
    let overlap_shape = Array::make(rank, 0)
    let mut elements = 1
    for axis in 0..<rank {
      source_shape[axis] = (seed + axis) % 4 + 2
      destination_shape[axis] = source_shape[axis] + 3
      overlap_origin[axis] = 1 + (seed + axis) % 2
      overlap_shape[axis] = source_shape[axis] - overlap_origin[axis] + 1
      elements *= overlap_shape[axis]
    }
    for fortran in [false, true] {
      let actual : Array[(Int, Int)] = []
      assert_true(
        @chunk.copy_region_spans(
          source_origin,
          source_shape,
          destination_origin,
          destination_shape,
          overlap_origin,
          overlap_shape,
          fn(source, destination, count, stride) {
            for i in 0..<count {
              actual.push((source + i * stride, destination + i))
            }
          },
          source_fortran=fortran,
        ),
      )
      assert_eq(actual.length(), elements)
      for linear in 0..<elements {
        let p = @chunk.region_coords(overlap_origin, overlap_shape, linear)
        let mut source = 0
        let mut stride = 1
        for step in 0..<rank {
          let axis = if fortran { step } else { rank - step - 1 }
          source += (p[axis] - 1) * stride
          stride *= source_shape[axis]
        }
        assert_eq(
          Some(actual[linear].1),
          @chunk.region_index(destination_origin, destination_shape, p),
        )
        assert_eq(actual[linear].0, source)
      }
    }
  }
}
