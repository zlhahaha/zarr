///|
pub(all) enum Entry {
  Absent
  Data(Int64, Int)
  Invalid
} derive(Debug)

///|
pub extend Entry with Debug::{to_repr}

///|
fn crc32c(bytes : BytesView) -> UInt {
  let mut crc = 0xFFFFFFFFU
  for byte in bytes {
    crc = crc ^ byte.to_uint()
    for _ in 0..<8 {
      crc = (crc >> 1) ^ (if (crc & 1U) == 1U { 0x82F63B78U } else { 0U })
    }
  }
  crc ^ 0xFFFFFFFFU
}

///|
fn index_u64(bytes : Bytes, at : Int, big_endian : Bool) -> UInt64? {
  if at < 0 || at > bytes.length() - 8 {
    return None
  }
  let view = bytes[at:at + 8]
  if big_endian {
    guard view is [u64be(value), ..] else { return None }
    Some(value)
  } else {
    guard view is [u64le(value), ..] else { return None }
    Some(value)
  }
}

///|
fn index_u32(bytes : Bytes, at : Int) -> UInt? {
  if at < 0 || at > bytes.length() - 4 {
    return None
  }
  guard bytes[at:at + 4] is [u32le(value), ..] else { return None }
  Some(value)
}

///|
/// An index whose length and optional CRC32C have been checked once.
/// Entry bounds are still checked for each selected inner chunk.
pub struct ValidatedIndex {
  layout : @metadata.Sharding
  bytes : Bytes
  shard_size : Int64
}

///|
pub fn validate_index(
  layout : @metadata.Sharding,
  index : Bytes,
  shard_size : Int64,
) -> ValidatedIndex? {
  if index.length() != layout.index_size ||
    shard_size < layout.index_size.to_int64() {
    return None
  }
  let data_size = index.length() - (if layout.index_crc32c { 4 } else { 0 })
  if layout.index_crc32c {
    guard index_u32(index, data_size) is Some(stored) else { return None }
    if crc32c(index[:data_size]) != stored {
      return None
    }
  }
  Some({ layout, bytes: index, shard_size, })
}

///|
pub fn ValidatedIndex::size_bytes(self : ValidatedIndex) -> Int {
  self.bytes.length()
}

///|
pub fn ValidatedIndex::matches_size(
  self : ValidatedIndex,
  size : Int64,
) -> Bool {
  self.shard_size == size
}

///|
pub fn ValidatedIndex::entry(
  self : ValidatedIndex,
  within : Array[Int],
) -> Entry {
  let layout = self.layout
  let index = self.bytes
  let shard_size = self.shard_size
  if within.length() != layout.chunks_per_shard.length() {
    return Invalid
  }
  let mut linear = 0
  for i in 0..<within.length() {
    let coord = within[i]
    let count = layout.chunks_per_shard[i]
    if coord < 0 || coord >= count {
      return Invalid
    }
    linear = linear * count + coord
  }
  let at = linear * 16
  guard index_u64(index, at, layout.index_big_endian) is Some(offset) else {
    return Invalid
  }
  guard index_u64(index, at + 8, layout.index_big_endian) is Some(length) else {
    return Invalid
  }
  if offset == 18446744073709551615UL && length == 18446744073709551615UL {
    return Absent
  }
  let start = if layout.index_at_start {
    layout.index_size.to_uint64()
  } else {
    0UL
  }
  let end = if layout.index_at_start {
    shard_size.reinterpret_as_uint64()
  } else {
    (shard_size - layout.index_size.to_int64()).reinterpret_as_uint64()
  }
  if offset < start ||
    offset >= end ||
    length == 0UL ||
    length > 67108864UL ||
    length > end - offset {
    return Invalid
  }
  Data(offset.reinterpret_as_int64(), length.to_int())
}

///|
/// Validate an index and identify one inner chunk without reading its payload.
/// For multiple entries use validate_index once, then ValidatedIndex::entry.
pub fn entry(
  layout : @metadata.Sharding,
  index : Bytes,
  within : Array[Int],
  shard_size : Int64,
) -> Entry {
  match validate_index(layout, index, shard_size) {
    Some(validated) => validated.entry(within)
    None => Invalid
  }
}
