///|
test "seed 424242: codec roundtrips random byte patterns and rejects wrong output sizes" {
  let mut state = 424242U
  for trial in 0..<48 {
    let size = trial * 13 + 1
    let input = Bytes::from_array(
      Array::makei(size, _ => {
        state = state * 1664525U + 1013904223U
        ((state >> 24) & 255U).to_byte()
      })[:],
    )
    for
      compression in [
        @codec.Raw,
        @codec.Gzip(1),
        @codec.Zlib(1),
        @codec.Zstd(1),
        @codec.BloscLz4(1, trial % 3, 1),
      ] {
      guard @codec.encode_chunk(compression, input) is Some(encoded) else {
        fail("encode")
      }
      assert_eq(@codec.decode_chunk(compression, encoded, size), Some(input))
      assert_true(@codec.decode_chunk(compression, encoded, size + 1) is None)
      assert_true(@codec.decode_chunk(compression, encoded, size - 1) is None)
      // Several truncation positions for every seeded input and codec.
      for end in [0, encoded.length() / 2, encoded.length() - 1] {
        assert_true(
          @codec.decode_chunk(compression, encoded[:end].to_owned(), size)
          is None,
        )
      }
    }
  }
}
