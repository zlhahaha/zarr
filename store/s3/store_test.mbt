///|
async test "S3 path-style SigV4 reader hydrates selected shard ranges" {
  guard @fs.FileStore::new(
      "integration/fixtures/zarr-python/v3_shard_start_u8.zarr",
    )
    is Some(files) else {
    fail("Python shard fixture")
  }
  guard @s3.Credentials::new(
      "example-access",
      "example-secret",
      session_token="session",
    )
    is Some(credentials) else {
    fail("credentials")
  }
  let server = @client_http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let signed = [0]
  let ranges = [0]
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((request, _body, conn) => {
        if request.headers.get("authorization") is None ||
          request.headers.get("x-amz-date") is None ||
          request.headers.get("x-amz-content-sha256") is None ||
          request.headers.get("x-amz-security-token") != Some("session") {
          conn.send_response(403, "Missing Signature")
          return
        }
        signed[0] += 1
        if !request.path.has_prefix("/bucket/dataset/") {
          conn.send_response(404, "Not Found")
          return
        }
        let key = request.path[16:].to_owned()
        match files.get(key) {
          None => conn.send_response(404, "Not Found")
          Some(bytes) =>
            match request.headers.get("range") {
              None => {
                conn.send_response(200, "OK")
                conn.write(bytes as &@io.Data)
              }
              Some(range) => {
                ranges[0] += 1
                let size = bytes.length()
                let (first, last) = if range.has_prefix("bytes=-") {
                  let suffix = @string.parse_int(range[7:]) catch {
                    _ => {
                      conn.send_response(400, "Bad Range")
                      return
                    }
                  }
                  (size - suffix, size - 1)
                } else {
                  guard range[6:].split_once("-") is Some((a, b)) else {
                    conn.send_response(400, "Bad Range")
                    return
                  }
                  let first = @string.parse_int(a) catch {
                    _ => {
                      conn.send_response(400, "Bad Range")
                      return
                    }
                  }
                  let last = @string.parse_int(b) catch {
                    _ => {
                      conn.send_response(400, "Bad Range")
                      return
                    }
                  }
                  (first, last)
                }
                if first < 0 || last < first || last >= size {
                  conn.send_response(416, "Range Not Satisfiable")
                  return
                }
                conn.send_response(
                  206,
                  "Partial Content",
                  extra_headers=Map([
                    ("Content-Range", "bytes \{first}-\{last}/\{size}"),
                    ("ETag", "\"stable\""),
                  ]),
                )
                conn.write(bytes[first:last + 1] as &@io.Data)
              }
            }
        }
      })
    }
    let endpoint = "http://127.0.0.1:\{server.addr.port()}"
    guard @s3.S3Store::new(
        "bucket",
        "us-east-1",
        prefix="dataset",
        endpoint~,
        credentials~,
      )
      is Some(s3) else {
      fail("S3 store")
    }
    guard s3.hydrate_region("", [0], [9]) is Some(cache) else {
      fail("S3 shard hydration")
    }
    guard @array.open_u8(cache, "") is Some(array) else {
      fail("S3 typed array")
    }
    assert_eq(
      array.read_region([0], [9]),
      Some(b"\x05\x0b\x05\x05\x05\x05\x16\x05\x21"),
    )
    assert_true(signed[0] >= 3)
    assert_true(ranges[0] >= 2)
  }
}
