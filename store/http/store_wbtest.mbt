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
