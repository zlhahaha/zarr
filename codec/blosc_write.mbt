///|
fn blosc_put_i32(output : Array[Byte], value : Int) -> Unit {
  output.push((value & 255).to_byte())
  output.push(((value >> 8) & 255).to_byte())
  output.push(((value >> 16) & 255).to_byte())
  output.push(((value >> 24) & 255).to_byte())
}

///|
fn blosc_lz4_hash(input : Bytes, at : Int) -> Int {
  (
    (input[at].to_int() << 8) ^
    (input[at + 1].to_int() << 4) ^
    (input[at + 2].to_int() << 2) ^
    input[at + 3].to_int()
  ) &
  65535
}

///|
fn blosc_lz4_extra(output : Array[Byte], length : Int) -> Unit {
  let mut remaining = length
  while remaining >= 255 {
    output.push(b'\xff')
    remaining -= 255
  }
  output.push(remaining.to_byte())
}

///|
fn blosc_lz4_match(
  output : Array[Byte],
  input : Bytes,
  anchor : Int,
  at : Int,
  previous : Int,
  match_length : Int,
) -> Unit {
  let literals = at - anchor
  let match_code = match_length - 4
  let token = ((if literals < 15 { literals } else { 15 }) << 4) |
    (if match_code < 15 { match_code } else { 15 })
  output.push(token.to_byte())
  if literals >= 15 {
    blosc_lz4_extra(output, literals - 15)
  }
  for i in anchor..<at {
    output.push(input[i])
  }
  let distance = at - previous
  output.push((distance & 255).to_byte())
  output.push((distance >> 8).to_byte())
  if match_code >= 15 {
    blosc_lz4_extra(output, match_code - 15)
  }
}

///|
/// A simple bounded-window LZ4 block encoder. It leaves at least five final
/// literals and starts its last match at least twelve bytes before the end.
fn blosc_lz4_encode(input : Bytes) -> Bytes {
  let seen = Array::make(65536, -1)
  let output : Array[Byte] = []
  let mut anchor = 0
  let mut at = 0
  while at <= input.length() - 12 {
    let hash = blosc_lz4_hash(input, at)
    let previous = seen[hash]
    seen[hash] = at
    if previous >= 0 &&
      at - previous <= 65535 &&
      input[previous] == input[at] &&
      input[previous + 1] == input[at + 1] &&
      input[previous + 2] == input[at + 2] &&
      input[previous + 3] == input[at + 3] {
      let mut length = 4
      while at + length < input.length() - 5 &&
            input[previous + length] == input[at + length] {
        length += 1
      }
      blosc_lz4_match(output, input, anchor, at, previous, length)
      at += length
      anchor = at
    } else {
      at += 1
    }
  }
  let literals = input.length() - anchor
  output.push(((if literals < 15 { literals } else { 15 }) << 4).to_byte())
  if literals >= 15 {
    blosc_lz4_extra(output, literals - 15)
  }
  for i in anchor..<input.length() {
    output.push(input[i])
  }
  Bytes::from_array(output)
}

///|
fn blosc_shuffle_bytes(raw : Bytes, typesize : Int, shuffle : Int) -> Bytes? {
  if typesize <= 0 || typesize > 255 || raw.length() % typesize != 0 {
    return None
  }
  if shuffle == 0 || (shuffle == 1 && typesize == 1) {
    return Some(raw)
  }
  let elements = raw.length() / typesize
  if shuffle == 1 {
    let output = Bytes::make(raw.length(), b'\x00').to_array()
    for element in 0..<elements {
      for lane in 0..<typesize {
        output[lane * elements + element] = raw[element * typesize + lane]
      }
    }
    return Some(Bytes::from_array(output[:]))
  }
  if shuffle != 2 {
    return None
  }
  if elements % 8 != 0 {
    return Some(raw)
  }
  let row_bytes = elements / 8
  let output = Bytes::make(raw.length(), b'\x00').to_array()
  for lane in 0..<typesize {
    for bit in 0..<8 {
      for group in 0..<row_bytes {
        let mut plane = 0
        for within in 0..<8 {
          let value = raw[(group * 8 + within) * typesize + lane].to_int()
          plane = plane | (((value >> bit) & 1) << within)
        }
        output[(lane * 8 + bit) * row_bytes + group] = plane.to_byte()
      }
    }
  }
  Some(Bytes::from_array(output[:]))
}

///|
/// Write a single-block Blosc1/LZ4 chunk. If compression does not save space,
/// use the format's memcpy representation so incompressible arrays stay small.
fn encode_blosc_lz4(
  raw : Bytes,
  level : Int,
  typesize : Int,
  shuffle : Int,
) -> Bytes? {
  if raw.length() <= 0 || raw.length() > 2147483000 {
    return None
  }
  guard blosc_shuffle_bytes(raw, typesize, shuffle) is Some(shuffled) else {
    return None
  }
  if level < 0 || level > 9 {
    return None
  }
  let compressed = if level == 0 { b"" } else { blosc_lz4_encode(shuffled) }
  let memcpy = level == 0 || compressed.length() + 24 >= raw.length() + 16
  let shuffle_flag = if shuffle == 1 { 1 } else if shuffle == 2 { 4 } else { 0 }
  let flags = 32 | shuffle_flag | (if memcpy { 2 } else { 16 })
  let output : Array[Byte] = [
    b'\x02',
    b'\x01',
    flags.to_byte(),
    typesize.to_byte(),
  ]
  blosc_put_i32(output, raw.length())
  blosc_put_i32(output, raw.length())
  blosc_put_i32(
    output,
    if memcpy {
      raw.length() + 16
    } else {
      compressed.length() + 24
    },
  )
  if memcpy {
    output.append(raw.to_array()[:])
  } else {
    blosc_put_i32(output, 20)
    blosc_put_i32(output, compressed.length())
    output.append(compressed.to_array()[:])
  }
  Some(Bytes::from_array(output))
}
