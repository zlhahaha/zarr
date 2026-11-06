///|
test "AWS published SigV4 GET Range vector" {
  guard Credentials::new(
      "AKIAIOSFODNN7EXAMPLE", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    )
    is Some(credentials) else {
    fail("credentials")
  }
  guard signature_headers(
      credentials,
      "us-east-1",
      "https://examplebucket.s3.amazonaws.com/test.txt",
      Some("bytes=0-9"),
      None,
      "20130524T000000Z",
    )
    is Some(headers) else {
    fail("signature")
  }
  assert_eq(
    headers.get("Authorization"),
    Some(
      "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,SignedHeaders=host;range;x-amz-content-sha256;x-amz-date,Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41",
    ),
  )
  assert_eq(headers.get("x-amz-date"), Some("20130524T000000Z"))
}

///|
test "SigV4 bucket listing matches independent botocore fixed-date vector" {
  guard Credentials::new(
      "AKIAIOSFODNN7EXAMPLE", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
    )
    is Some(credentials) else {
    fail("credentials")
  }
  guard signature_headers(
      credentials,
      "us-east-1",
      "https://examplebucket.s3.amazonaws.com/",
      None,
      None,
      "20130524T000000Z",
      query="max-keys=2&prefix=J",
    )
    is Some(headers) else {
    fail("headers")
  }
  guard headers.get("Authorization") is Some(value) else {
    fail("authorization")
  }
  assert_true(
    value.has_suffix(
      "Signature=34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7",
    ),
  )
}

///|
test "S3 address configuration validates bucket and path" {
  assert_true(S3Store::new("valid-bucket", "us-east-1") is Some(_))
  assert_true(S3Store::new("bad/bucket", "us-east-1") is None)
  assert_true(S3Store::new("valid", "us-east-1", prefix="../x") is None)
  assert_true(
    S3Store::new("valid", "us-east-1", endpoint="file:///tmp") is None,
  )
  assert_true(S3Store::new("valid", "us-east-1", request_timeout_ms=0) is None)
}

///|
test "signed plaintext endpoints require explicit opt in" {
  guard Credentials::new("test-access", "test-secret", session_token="token")
    is Some(credentials) else {
    fail("test credentials")
  }
  for
    endpoint in [
      "http://127.0.0.1:9000", "http://localhost:9000", "http://storage.example",
    ] {
    assert_true(
      S3Store::new("bucket", "us-east-1", endpoint~, credentials~) is None,
    )
    assert_true(
      S3Store::new(
        "bucket",
        "us-east-1",
        endpoint~,
        credentials~,
        allow_insecure_http=true,
      )
      is Some(_),
    )
    assert_true(S3Store::new("bucket", "us-east-1", endpoint~) is Some(_))
  }
  assert_true(S3Store::new("bucket", "us-east-1", credentials~) is Some(_))
  assert_true(
    S3Store::new(
      "bucket",
      "us-east-1",
      endpoint="https://storage.example",
      credentials~,
    )
    is Some(_),
  )
}
