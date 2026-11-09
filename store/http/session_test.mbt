///|
async test "session pins metadata without repeated probes and refresh isolates cached objects" {
  let server = @client_http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let mut revision = 0
  let mut probes = 0
  let mut payloads = 0
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((request, _body, connection) => {
        let path = request.path
        if path == "/a/.zarray" {
          probes += 1
          let shape = if revision == 0 { 4 } else { 2 }
          let raw = "{\"zarr_format\":2,\"shape\":[\{shape}],\"chunks\":[2],\"dtype\":\"|u1\",\"fill_value\":5,\"order\":\"C\",\"filters\":null,\"compressor\":null}"
          connection.send_response(200, "OK")
          connection.write(@utf8.encode(raw) as &@io.Data)
        } else if path == "/a/.zgroup" || path == "/a/zarr.json" {
          probes += 1
          connection.send_response(404, "Missing")
        } else if path == "/a/0" {
          payloads += 1
          connection.send_response(200, "OK")
          connection.write(
            (if revision == 0 { b"\x01\x02" } else { b"\x09\x0a" }) as &@io.Data,
          )
        } else {
          connection.send_response(404, "Missing")
        }
      })
    }
    guard @http.HttpStore::new("http://127.0.0.1:\{server.addr.port()}")
      is Some(http) else {
      fail("http")
    }
    guard http.open_array_session_result("a") is Ok(old) else {
      fail("session")
    }
    assert_eq(probes, 3)
    let copy = old.metadata()
    copy.shape[0] = 999
    assert_eq(old.metadata().shape, [4])
    for _ in 0..<3 {
      guard old.hydrate_region_result([0], [2]) is Ok(memory) else {
        fail("hydrate")
      }
      guard @array.open_u8(memory, "a") is Some(array) else { fail("open") }
      assert_eq(array.read_region([0], [2]), Some(b"\x01\x02"))
    }
    assert_eq(probes, 3)
    assert_eq(payloads, 1)
    revision = 1
    guard old.refresh() is Ok(fresh) else { fail("refresh") }
    assert_eq(probes, 6)
    assert_eq(fresh.metadata().shape, [2])
    assert_eq(old.metadata().shape, [4])
    assert_true(
      fresh.hydrate_region_result([2], [1]) is Err(@store.InvalidRegion(_)),
    )
    guard fresh.hydrate_region_result([0], [2]) is Ok(memory) else {
      fail("new hydrate")
    }
    guard @array.open_u8(memory, "a") is Some(array) else { fail("new open") }
    assert_eq(array.read_region([0], [2]), Some(b"\x09\x0a"))
    assert_eq(probes, 6)
    assert_eq(payloads, 2)
    guard old.hydrate_region_result([0], [2]) is Ok(old_memory) else {
      fail("old hydrate")
    }
    guard @array.open_u8(old_memory, "a") is Some(old_array) else {
      fail("old open")
    }
    assert_eq(old_array.read_region([0], [2]), Some(b"\x01\x02"))
    assert_eq(payloads, 2)
    assert_true(
      http.open_array_session_result("../bad") is Err(@store.InvalidPath(_)),
    )
  }
}
