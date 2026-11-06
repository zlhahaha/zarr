///|
fn page(body : String) -> String {
  "<?xml version=\"1.0\" encoding=\"UTF-8\"?><ListBucketResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\"><Prefix>dataset%2F</Prefix><Delimiter>%2F</Delimiter><EncodingType>url</EncodingType>\{body}</ListBucketResult>"
}

///|
test "S3 page parser validates encoded keys and opaque continuation tokens" {
  guard parse_list_page(
      page(
        "<KeyCount>2</KeyCount><IsTruncated>true</IsTruncated><CommonPrefixes><Prefix>dataset%2F%CE%BC%20%26%20%E5%9B%BE%2F</Prefix></CommonPrefixes><Contents><Key>dataset%2Fzarr.json</Key></Contents><NextContinuationToken>a+b/=&#38;x</NextContinuationToken>",
      ),
      "dataset/",
      2,
    )
    is Some(parsed) else {
    fail("valid page")
  }
  assert_eq(parsed.prefixes, ["dataset/μ & 图/"])
  assert_eq(parsed.entries, 2)
  assert_eq(parsed.next, Some("a+b/=&x"))
  assert_eq(uri_encode("a+b/=&x"), "a%2Bb%2F%3D%26x")
  assert_eq(uri_decode(uri_encode("μ & 图/+")), Some("μ & 图/+"))
  assert_eq(uri_decode("a+b%2Bc"), Some("a b+c"))
  assert_true(uri_decode("%FF") is None)
  assert_true(uri_decode("%2") is None)
  assert_true(xml_text("&unknown;") is None)
  assert_eq(xml_text("&#x1F600;&lt;&amp;"), Some("😀<&"))
  assert_true(xml_text("&#0;") is None)
}

///|
test "S3 page parser rejects malformed truncated or unbounded XML" {
  let valid = page("<KeyCount>0</KeyCount><IsTruncated>false</IsTruncated>")
  assert_true(parse_list_page(valid, "dataset/", 2) is Some(_))
  for
    raw in [
      valid + "garbage",
      valid.replace_all(old="</KeyCount>", new="</Wrong>"),
      valid.replace_all(
        old="<KeyCount>0</KeyCount>",
        new="<KeyCount>0</KeyCount><KeyCount>0</KeyCount>",
      ),
      valid.replace_all(old="false", new="true"),
      valid.replace_all(old="dataset%2F", new="other%2F"),
      valid.replace_all(
        old="<KeyCount>0</KeyCount>",
        new="<KeyCount>1</KeyCount>",
      ),
      "<!DOCTYPE x [<!ENTITY leak SYSTEM 'file:///private'>]>" + valid,
      valid.replace_all(
        old="</ListBucketResult>",
        new="<Other>&leak;</Other></ListBucketResult>",
      ),
    ] {
    assert_true(parse_list_page(raw, "dataset/", 2) is None)
  }
  let mut nested = ""
  for _ in 0..<20 {
    nested += "<Other>"
  }
  for _ in 0..<20 {
    nested += "</Other>"
  }
  assert_true(
    parse_list_page(
      page("<KeyCount>0</KeyCount><IsTruncated>false</IsTruncated>" + nested),
      "dataset/",
      2,
    )
    is None,
  )
}
