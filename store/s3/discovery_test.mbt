///|
async test "S3 discovery rejects malformed pagination and preserves listing permission failures" {
  let server = @client_http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let mode = Ref("repeat")
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((request, _body, connection) => {
        if request.path.has_suffix("/zarr.json") {
          connection.send_response(200, "OK")
          connection.write(
            b"{\"zarr_format\":3,\"node_type\":\"group\",\"attributes\":{}}"
            as &@io.Data,
          )
        } else if request.path.has_suffix("/.zarray") ||
          request.path.has_suffix("/.zgroup") {
          connection.send_response(404, "Missing")
        } else if mode.val == "denied" {
          connection.send_response(403, "ListBucket denied")
        } else {
          let body = if mode.val == "bad" {
            "<ListBucketResult><unclosed>"
          } else {
            let child = if mode.val == "outside" { "../" } else { "child/" }
            "<ListBucketResult><Prefix/><Delimiter>/</Delimiter><EncodingType>url</EncodingType><KeyCount>1</KeyCount><CommonPrefixes><Prefix>\{child}</Prefix></CommonPrefixes><IsTruncated>true</IsTruncated><NextContinuationToken>repeat</NextContinuationToken></ListBucketResult>"
          }
          connection.send_response(200, "OK")
          connection.write(@utf8.encode(body) as &@io.Data)
        }
      })
    }
    let endpoint = "http://127.0.0.1:\{server.addr.port()}"
    guard @s3.S3Store::new("bucket", "us-east-1", endpoint~) is Some(remote) else {
      fail("store")
    }
    assert_true(
      remote.list_children_result("")
      is Err(@store.Protocol("", "repeated continuation token")),
    )
    mode.val = "outside"
    assert_true(remote.list_children_result("") is Err(@store.Protocol(_, _)))
    mode.val = "bad"
    assert_true(
      remote.list_children_result("")
      is Err(@store.Protocol("", "invalid ListObjectsV2 XML")),
    )
    mode.val = "denied"
    assert_true(
      remote.list_children_result("") is Err(@store.Authentication("", 403)),
    )
  }
}
