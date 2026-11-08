///|
async test "automatic remote tiles handle missing fills, decode failure, auth and early stop" {
  let server = @server_http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let metadata = b"{\"zarr_format\":2,\"shape\":[5],\"chunks\":[2],\"dtype\":\"|u1\",\"fill_value\":7,\"order\":\"C\",\"filters\":null,\"compressor\":null}"
  let mut payloads = 0
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((request, _body, connection) => {
        let path = request.path
        if path.has_prefix("/denied/") {
          connection.send_response(403, "Denied")
        } else if path == "/u16/.zarray" || path == "/float/.zarray" {
          connection.send_response(200, "OK")
          let description = if path == "/u16/.zarray" {
            b"{\"zarr_format\":2,\"shape\":[3],\"chunks\":[2],\"dtype\":\">u2\",\"fill_value\":7,\"order\":\"C\",\"filters\":null,\"compressor\":null}"
          } else {
            b"{\"zarr_format\":2,\"shape\":[3],\"chunks\":[2],\"dtype\":\"<f4\",\"fill_value\":-1.5,\"order\":\"C\",\"filters\":null,\"compressor\":null}"
          }
          connection.write(description as &@io.Data)
        } else if path == "/u16/0" || path == "/float/0" {
          connection.send_response(200, "OK")
          let data = if path == "/u16/0" {
            b"\x00\x01\x00\x02"
          } else {
            b"\x00\x00\xa0\x3f\x00\x00\x20\x40"
          }
          connection.write(data as &@io.Data)
        } else if path.has_suffix("/.zarray") {
          connection.send_response(200, "OK")
          connection.write(metadata as &@io.Data)
        } else if path == "/a/0" || path == "/a/2" || path == "/broken/0" {
          payloads += 1
          connection.send_response(200, "OK")
          let data = if path == "/a/0" {
            b"\x01\x02"
          } else if path == "/a/2" {
            b"\x09\x00"
          } else {
            b"\x01"
          }
          connection.write(data as &@io.Data)
        } else {
          connection.send_response(404, "Missing")
        }
      })
    }
    guard @http.HttpStore::new(
        "http://127.0.0.1:\{server.addr.port()}",
        max_cache_bytes=0,
      )
      is Some(http) else {
      fail("http")
    }
    let source = @remote.Source::http(http)
    guard source.open_u8("a", [0], [5], [3]) is Ok(reader) else { fail("open") }
    assert_eq(payloads, 0)
    guard reader.next() is Ok(Some(first)) else { fail("first") }
    assert_eq(first.values, [b'\x01', b'\x02', b'\x07'])
    guard reader.next() is Ok(Some(last)) else { fail("last") }
    assert_eq(last.origin, [3])
    assert_eq(last.values, [b'\x07', b'\x09'])
    assert_true(reader.next() is Ok(None))
    assert_eq(payloads, 2)
    guard source.open_u8("a", [0], [5], [2]) is Ok(stopped) else {
      fail("stop")
    }
    assert_true(stopped.next() is Ok(Some(_)))
    stopped.close()
    assert_true(stopped.next() is Ok(None))
    assert_eq(payloads, 3)
    assert_true(
      source.open_u8("denied", [0], [1], [1])
      is Err(@store.Authentication(_, 403)),
    )
    assert_true(
      source.open_u8("a", [4], [2], [1]) is Err(@store.InvalidRegion(_)),
    )
    guard source.open_u8("broken", [0], [2], [2]) is Ok(broken) else {
      fail("broken")
    }
    assert_true(
      broken.next() is Err(@store.Protocol(_, "typed tile decode rejected")),
    )
    assert_true(broken.next() is Err(@store.Protocol(_, _)))
    assert_eq(payloads, 4)
    guard source.open_u16("a", [0], [2], [2]) is Ok(wrong_dtype) else {
      fail("wrong dtype reader")
    }
    assert_true(wrong_dtype.next() is Err(@store.Protocol(_, _)))
    guard source.open_u16("u16", [0], [3], [3]) is Ok(integers) else {
      fail("uint16")
    }
    guard integers.next() is Ok(Some(tile)) else { fail("uint16 tile") }
    assert_eq(tile.values, [(1 : UInt16), (2 : UInt16), (7 : UInt16)])
    guard source.open_f32("float", [0], [3], [3]) is Ok(floats) else {
      fail("float32")
    }
    guard floats.next() is Ok(Some(tile)) else { fail("float32 tile") }
    assert_eq(tile.values, [1.25F, 2.5F, -1.5F])
  }
}
