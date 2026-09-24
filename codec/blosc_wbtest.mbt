///|
test "LZ4 split decoder rejects malformed lengths and references" {
  assert_eq(blosc_lz4(b"\x30abc", 3), Some(b"abc"))
  assert_eq(blosc_lz4(b"\x10a\x01\x00\x10b", 6), Some(b"aaaaab"))
  assert_true(blosc_lz4(b"\x20a", 2) is None)
  assert_true(blosc_lz4(b"\x10a\x00\x00\x10b", 6) is None)
  assert_true(blosc_lz4(b"\x30abc", 4) is None)
}

///|
test "Blosc header enforces declared size and format" {
  let memcpy = b"\x02\x01\x22\x01\x03\x00\x00\x00\x03\x00\x00\x00\x13\x00\x00\x00abc"
  assert_eq(decode_blosc(memcpy, 3, "lz4"), Some(b"abc"))
  assert_true(decode_blosc(memcpy, 2, "lz4") is None)
  assert_true(decode_blosc(memcpy, 3, "zstd") is None)
  let bad_version = b"\x03\x01\x22\x01\x03\x00\x00\x00\x03\x00\x00\x00\x13\x00\x00\x00abc"
  assert_true(decode_blosc(bad_version, 3, "lz4") is None)
  let bad_length = b"\x02\x01\x22\x01\x03\x00\x00\x00\x03\x00\x00\x00\x12\x00\x00\x00abc"
  assert_true(decode_blosc(bad_length, 3, "lz4") is None)
  let invalid_flags = b"\x02\x01\x27\x01\x03\x00\x00\x00\x03\x00\x00\x00\x13\x00\x00\x00abc"
  assert_true(decode_blosc(invalid_flags, 3, "lz4") is None)
}

///|
test "Blosc bitshuffle inverse preserves bit planes and short blocks" {
  let planes = [
    b'\xaa', b'\xcc', b'\xf0', b'\x00', b'\x00', b'\x00', b'\x00', b'\x00',
  ]
  assert_eq(
    blosc_bitunshuffle(planes, 1),
    Some(b"\x00\x01\x02\x03\x04\x05\x06\x07"),
  )
  assert_eq(blosc_bitunshuffle([b'a', b'b', b'c'], 1), Some(b"abc"))
  assert_true(blosc_bitunshuffle([b'a', b'b', b'c'], 2) is None)
}
