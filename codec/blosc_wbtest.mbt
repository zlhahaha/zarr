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

///|
test "Blosc LZ4 writer roundtrips byte and bit shuffle" {
  for typesize in [1, 2, 4, 8] {
    for shuffle in [0, 1, 2] {
      let bytes : Array[Byte] = []
      for i in 0..<1024 {
        bytes.push((i % 37).to_byte())
      }
      let raw = Bytes::from_array(bytes)
      guard encode_blosc_lz4(raw, 5, typesize, shuffle) is Some(encoded) else {
        fail("Blosc encoding")
      }
      assert_eq(decode_blosc(encoded, raw.length(), "lz4"), Some(raw))
      assert_eq(encoded[3].to_int(), typesize)
    }
  }
}

///|
test "Blosc LZ4 writer handles short bitshuffle and memcpy fallback" {
  let short = b"abcde"
  guard encode_blosc_lz4(short, 5, 1, 2) is Some(encoded) else {
    fail("short bitshuffle encoding")
  }
  assert_eq(decode_blosc(encoded, 5, "lz4"), Some(short))
  assert_true((encoded[2].to_int() & 2) != 0)
  let bytes : Array[Byte] = []
  for i in 0..<4096 {
    bytes.push(((i * 73 + 19) % 251).to_byte())
  }
  let raw = Bytes::from_array(bytes)
  guard encode_blosc_lz4(raw, 5, 1, 0) is Some(frame) else {
    fail("LZ4 encoding")
  }
  assert_eq(decode_blosc(frame, raw.length(), "lz4"), Some(raw))
  assert_true(encode_blosc_lz4(b"abc", 5, 2, 1) is None)
  assert_true(encode_blosc_lz4(b"abc", 5, 1, 3) is None)
  guard encode_blosc_lz4(b"aaaabbbb", 0, 1, 0) is Some(uncompressed) else {
    fail("level-zero Blosc frame")
  }
  assert_true((uncompressed[2].to_int() & 2) != 0)
}
