///|
async test "HTTP range hydration reads Python start/end shards" {
  let base = "integration/fixtures/zarr-python"
  guard @fs.FileStore::new("\{base}/v3_shard_start_u8.zarr")
    is Some(start_files) else {
    fail("start fixture")
  }
  guard @fs.FileStore::new("\{base}/v3_shard_end_gzip_u16.zarr")
    is Some(end_files) else {
    fail("end fixture")
  }
  let server = @client_http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let range_requests = [0]
  let full_shards = [0]
  let mode = [""]
  let retries = [0]
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((request, _body, conn) => {
        let route = request.path[1:].to_owned()
        let (files, key) = if route.has_prefix("start/") {
          (start_files, route[6:].to_owned())
        } else if route.has_prefix("end/") {
          (end_files, route[4:].to_owned())
        } else {
          (start_files, "missing")
        }
        match files.get(key) {
          None => conn.send_response(404, "Not Found")
          Some(bytes) => {
            if key.has_prefix("c/") && mode[0] == "deny" {
              conn.send_response(403, "Forbidden")
              return
            }
            if key.has_prefix("c/") && mode[0] == "retry" && retries[0] == 0 {
              retries[0] += 1
              conn.send_response(503, "Service Unavailable")
              return
            }
            match request.headers.get("range") {
              None => {
                if key.has_prefix("c/") {
                  full_shards[0] += 1
                }
                conn.send_response(200, "OK")
                conn.write(bytes as &@io.Data)
              }
              Some(range) => {
                range_requests[0] += 1
                if mode[0] == "ignore" {
                  conn.send_response(200, "OK")
                  conn.write(bytes as &@io.Data)
                  return
                }
                if mode[0] == "conflict" &&
                  request.headers.get("if-match") is Some(_) {
                  conn.send_response(412, "Precondition Failed")
                  return
                }
                if !range.has_prefix("bytes=") {
                  conn.send_response(400, "Bad Request")
                  return
                }
                let size = bytes.length()
                let (first, last) = if range.has_prefix("bytes=-") {
                  let suffix = @string.parse_int(range[7:]) catch {
                    _ => {
                      conn.send_response(400, "Bad Request")
                      return
                    }
                  }
                  (size - suffix, size - 1)
                } else {
                  guard range[6:].split_once("-") is Some((first, last)) else {
                    conn.send_response(400, "Bad Request")
                    return
                  }
                  let first = @string.parse_int(first) catch {
                    _ => {
                      conn.send_response(400, "Bad Request")
                      return
                    }
                  }
                  let last = @string.parse_int(last) catch {
                    _ => {
                      conn.send_response(400, "Bad Request")
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
                    (
                      "Content-Range",
                      if mode[0] == "bad-range" {
                        "bytes 0-0/1"
                      } else {
                        "bytes \{first}-\{last}/\{size}"
                      },
                    ),
                    ("ETag", "\"stable-fixture\""),
                  ]),
                )
                conn.write(bytes[first:last + 1] as &@io.Data)
              }
            }
          }
        }
      })
    }
    let root = "http://127.0.0.1:\{server.addr.port()}"
    guard @http.HttpStore::new("\{root}/start") is Some(start) else {
      fail("start store")
    }
    guard start.hydrate_region("", [0], [9]) is Some(start_cache) else {
      fail("start hydration")
    }
    guard @array.open_u8(start_cache, "") is Some(u8) else {
      fail("start array")
    }
    assert_eq(
      u8.read_region([0], [9]),
      Some(b"\x05\x0b\x05\x05\x05\x05\x16\x05\x21"),
    )
    guard @http.HttpStore::new("\{root}/end") is Some(end_store) else {
      fail("end store")
    }
    guard end_store.hydrate_region("", [0, 0], [5, 7]) is Some(end_cache) else {
      fail("end hydration")
    }
    guard @array.open_u16(end_cache, "") is Some(u16) else { fail("end array") }
    assert_eq(u16.read([0, 0]), Some((7 : UInt16)))
    assert_eq(u16.read([2, 5]), Some((114 : UInt16)))
    assert_true(range_requests[0] > 2)
    assert_eq(full_shards[0], 0)
    mode[0] = "ignore"
    guard @http.HttpStore::new("\{root}/start") is Some(ignore) else {
      fail("ignore store")
    }
    assert_true(ignore.hydrate_region("", [0], [2]) is None)
    mode[0] = "bad-range"
    guard @http.HttpStore::new("\{root}/start") is Some(bad) else {
      fail("bad range store")
    }
    assert_true(bad.hydrate_region("", [0], [2]) is None)
    mode[0] = "deny"
    guard @http.HttpStore::new("\{root}/start") is Some(denied) else {
      fail("denied store")
    }
    assert_true(denied.hydrate_region("", [0], [2]) is None)
    mode[0] = "conflict"
    guard @http.HttpStore::new("\{root}/start") is Some(conflict) else {
      fail("conflict store")
    }
    assert_true(conflict.hydrate_region("", [0], [2]) is None)
    mode[0] = "retry"
    guard @http.HttpStore::new("\{root}/start") is Some(retrying) else {
      fail("retry store")
    }
    assert_true(retrying.hydrate_region("", [0], [2]) is Some(_))
    assert_eq(retries[0], 1)
    mode[0] = ""
    guard @http.HttpStore::new("\{root}/start", max_hydration_bytes=1)
      is Some(tiny) else {
      fail("tiny range budget")
    }
    assert_true(tiny.hydrate_region("", [0], [2]) is None)
  }
}
