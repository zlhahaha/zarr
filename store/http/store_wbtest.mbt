///|
test "HTTP keys are escaped without changing chunk separators" {
  assert_eq(
    encode_key("science data/μ.zarray"),
    Some("science%20data/%CE%BC.zarray"),
  )
  assert_eq(encode_key("a?b/c#d"), Some("a%3Fb/c%23d"))
  assert_true(encode_key("a/../b") is None)
  assert_true(encode_key("a//b") is None)
}

///|
test "HTTP cache evicts least recently used entries within both caps" {
  guard HttpStore::new(
      "http://127.0.0.1",
      max_cache_bytes=4,
      max_cache_entries=2,
    )
    is Some(remote) else {
    fail("cache config")
  }
  remote.cache_found("a", b"aa")
  remote.cache_found("b", b"bb")
  assert_true(remote.cached("a", 2) is Some(Found(_)))
  remote.cache_found("c", b"cc")
  assert_true(remote.cached("b", 2) is None)
  assert_true(remote.cached("a", 2) is Some(Found(_)))
  assert_true(remote.cached("c", 2) is Some(Found(_)))
  assert_eq(remote.cache_bytes, 4)
  assert_eq(remote.cache_entries, 2)
  remote.cache_found("large", b"12345")
  remote.cache_found("empty", b"")
  assert_true(remote.cached("large", 5) is None)
  assert_true(remote.cached("empty", 0) is None)
  assert_true(remote.cached("a", 1) is Some(Failed))
}
