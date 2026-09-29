///|
/// Check the encoded object and expected decoded size before invoking codecs.
fn decode_read_chunk(
  store : @store.MemoryStore,
  compression : @codec.Compression,
  encoded : Bytes,
  expected : Int,
) -> Bytes? {
  if !store.read_limits().allows_decode(encoded.length(), expected) {
    return None
  }
  @codec.decode_chunk(compression, encoded, expected)
}
