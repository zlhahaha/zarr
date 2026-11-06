///|
async test "remote Result APIs preserve HTTP timeout protocol and budget causes" {
  let server = @client_http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let valid = b"{\"zarr_format\":2,\"shape\":[3],\"chunks\":[2],\"dtype\":\"|u1\",\"fill_value\":5,\"order\":\"C\",\"filters\":null,\"compressor\":null}"
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((request, _body, connection) => {
        let path = request.path
        if path.has_prefix("/deny/") {
          connection.send_response(403, "Denied")
          return
        }
        if path.has_prefix("/auth/") {
          connection.send_response(401, "Auth")
          return
        }
        if path.has_prefix("/conflict/") {
          connection.send_response(412, "Changed")
          return
        }
        if path.has_prefix("/busy/") {
          connection.send_response(503, "Busy")
          return
        }
        if path.has_prefix("/slow/") {
          @async.sleep(500)
          connection.send_response(404, "Missing")
          return
        }
        if path.has_suffix("/.zarray") && !path.has_prefix("/missing/") {
          connection.send_response(200, "OK")
          connection.write(
            (if path.has_prefix("/bad/") { b"bad" } else { valid }) as &@io.Data,
          )
        } else {
          connection.send_response(404, "Missing")
        }
      })
    }
    let base = "http://127.0.0.1:\{server.addr.port()}"
    guard @http.HttpStore::new(base, request_timeout_ms=50) is Some(remote) else {
      fail("store")
    }
    assert_true(
      remote.open_array_result("deny") is Err(@store.Authentication(_, 403)),
    )
    assert_true(
      remote.open_array_result("auth") is Err(@store.Authentication(_, 401)),
    )
    assert_true(remote.open_array_result("conflict") is Err(@store.Conflict(_)))
    assert_true(
      remote.open_array_result("busy") is Err(@store.HttpStatus(_, 503)),
    )
    assert_true(remote.open_array_result("slow") is Err(@store.Timeout(_)))
    assert_true(
      remote.open_array_result("missing") is Err(@store.NotFound("missing")),
    )
    assert_true(
      remote.open_array_result("bad") is Err(@store.InvalidMetadata("bad")),
    )
    assert_true(remote.open_array_result("../x") is Err(@store.InvalidPath(_)))
    assert_true(remote.open_array_result("good") is Ok(_))
    assert_true(
      remote.hydrate_region_result("good", [2], [2])
      is Err(@store.InvalidRegion(_)),
    )
    guard @http.HttpStore::new(base, max_metadata_bytes=4) is Some(small) else {
      fail("small")
    }
    assert_true(
      small.open_array_result("good") is Err(@store.LimitExceeded(_, _)),
    )
    let rejected = remote.with_get_headers(fn(_, _, _) { None })
    assert_true(
      rejected.open_array_result("good") is Err(@store.HeaderRejected(_)),
    )
    assert_true(
      rejected.open_array_result("uncached") is Err(@store.HeaderRejected(_)),
    )
    assert_true(remote.open_array("deny") is None)
    assert_true(remote.open_array("good") is Some(_))
    assert_true(remote.open_array("/good/") is Some(_))
    assert_true(
      remote.open_array_result("/good/") is Err(@store.InvalidPath(_)),
    )
  }
}
