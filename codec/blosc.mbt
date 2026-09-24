///|
/// Read a nonnegative little-endian 32-bit length without overflowing Int.
fn blosc_i32(bytes : Bytes, at : Int) -> Int? {
  if at < 0 ||
    bytes.length() < 4 ||
    at > bytes.length() - 4 ||
    bytes[at + 3].to_int() >= 128 {
    return None
  }
  Some(
    bytes[at].to_int() |
    (bytes[at + 1].to_int() << 8) |
    (bytes[at + 2].to_int() << 16) |
    (bytes[at + 3].to_int() << 24),
  )
}

///|
/// Decode one raw LZ4 block, enforcing its expected uncompressed size.
fn blosc_lz4(input : Bytes, expected : Int) -> Bytes? {
  if expected < 0 {
    return None
  }
  let output = Bytes::make(expected, b'\x00').to_array()
  let mut input_at = 0
  let mut output_at = 0
  while input_at < input.length() {
    let token = input[input_at].to_int()
    input_at += 1
    let mut literal_len = token >> 4
    if literal_len == 15 {
      for ;; {
        if input_at >= input.length() {
          return None
        }
        let extra = input[input_at].to_int()
        input_at += 1
        if extra > expected - literal_len {
          return None
        }
        literal_len += extra
        if extra != 255 {
          break
        }
      }
    }
    if literal_len > expected - output_at ||
      literal_len > input.length() - input_at {
      return None
    }
    for i in 0..<literal_len {
      output[output_at + i] = input[input_at + i]
    }
    input_at += literal_len
    output_at += literal_len
    if input_at == input.length() {
      return if output_at == expected {
        Some(Bytes::from_array(output[:]))
      } else {
        None
      }
    }
    if input.length() - input_at < 2 {
      return None
    }
    let distance = input[input_at].to_int() +
      (input[input_at + 1].to_int() << 8)
    input_at += 2
    if distance == 0 || distance > output_at {
      return None
    }
    let mut match_len = (token & 15) + 4
    if (token & 15) == 15 {
      for ;; {
        if input_at >= input.length() {
          return None
        }
        let extra = input[input_at].to_int()
        input_at += 1
        if extra > expected - match_len {
          return None
        }
        match_len += extra
        if extra != 255 {
          break
        }
      }
    }
    if match_len > expected - output_at {
      return None
    }
    for i in 0..<match_len {
      output[output_at + i] = output[output_at + i - distance]
    }
    output_at += match_len
  }
  None
}

///|
fn blosc_split(
  encoded : Bytes,
  start : Int,
  size : Int,
  expected : Int,
  cname : String,
) -> Bytes? {
  if start < 0 || size < 0 || start > encoded.length() - size {
    return None
  }
  let input = Bytes::from_array(encoded[start:start + size].to_array())
  match cname {
    "lz4" | "lz4hc" => blosc_lz4(input, expected)
    "zlib" => decode_zlib(input, expected)
    "zstd" => decode_zstd(input, expected)
    _ => None
  }
}

///|
/// Decode the common Blosc1 chunk format (format byte 2) used by Zarr. Unsupported
/// compressors and bitshuffle are rejected before bytes reach the dtype layer.
fn decode_blosc(encoded : Bytes, expected : Int, cname : String) -> Bytes? {
  if expected <= 0 || encoded.length() < 16 || encoded[0] != b'\x02' {
    return None
  }
  let flags = encoded[2].to_int()
  if (flags & 8) != 0 || (flags & 4) != 0 {
    return None
  }
  let compressor_id = flags >> 5
  let expected_id = match cname {
    "lz4" | "lz4hc" => 1
    "zlib" => 3
    "zstd" => 4
    _ => return None
  }
  if compressor_id != expected_id {
    return None
  }
  let typesize = encoded[3].to_int()
  if typesize == 0 {
    return None
  }
  guard blosc_i32(encoded, 4) is Some(nbytes) else { return None }
  guard blosc_i32(encoded, 8) is Some(blocksize) else { return None }
  guard blosc_i32(encoded, 12) is Some(cbytes) else { return None }
  if nbytes != expected || cbytes != encoded.length() || blocksize <= 0 {
    return None
  }
  if (flags & 2) != 0 {
    if cbytes - 16 != nbytes {
      return None
    }
    return Some(Bytes::from_array(encoded[16:].to_array()))
  }
  let blocks = (nbytes - 1) / blocksize + 1
  if blocks > (cbytes - 16) / 4 {
    return None
  }
  let table_end = 16 + blocks * 4
  let output = Bytes::make(nbytes, b'\x00').to_array()
  let mut previous_end = table_end
  for block in 0..<blocks {
    guard blosc_i32(encoded, 16 + block * 4) is Some(start) else { return None }
    let end = if block + 1 == blocks {
      cbytes
    } else {
      guard blosc_i32(encoded, 16 + (block + 1) * 4) is Some(next) else {
        return None
      }
      next
    }
    if start != previous_end || end < start || end > cbytes {
      return None
    }
    let block_at = block * blocksize
    let block_len = if blocksize > nbytes - block_at {
      nbytes - block_at
    } else {
      blocksize
    }
    let splits = if (flags & 16) != 0 || typesize == 1 { 1 } else { typesize }
    if block_len % splits != 0 {
      return None
    }
    let split_len = block_len / splits
    let shuffled = Bytes::make(block_len, b'\x00').to_array()
    let mut cursor = start
    for split in 0..<splits {
      if cursor > end - 4 {
        return None
      }
      guard blosc_i32(encoded, cursor) is Some(size) else { return None }
      cursor += 4
      if size == 0 || size > end - cursor {
        return None
      }
      guard blosc_split(encoded, cursor, size, split_len, cname)
        is Some(decoded) else {
        return None
      }
      for i in 0..<split_len {
        shuffled[split * split_len + i] = decoded[i]
      }
      cursor += size
    }
    if cursor != end {
      return None
    }
    if (flags & 1) != 0 {
      if block_len % typesize != 0 {
        return None
      }
      let elements = block_len / typesize
      for element in 0..<elements {
        for lane in 0..<typesize {
          output[block_at + element * typesize + lane] = shuffled[lane *
            elements +
            element]
        }
      }
    } else {
      for i in 0..<block_len {
        output[block_at + i] = shuffled[i]
      }
    }
    previous_end = end
  }
  Some(Bytes::from_array(output[:]))
}
