///|
async test "HTTP hydration reads only a bounded remote region" {
  let base = "integration/fixtures/zarr-python"
  guard @fs.FileStore::new("\{base}/v2_grouped_u8.zarr") is Some(v2_files) else {
    fail("v2 fixture")
  }
  guard @fs.FileStore::new("\{base}/v3_grouped_u8.zarr") is Some(v3_files) else {
    fail("v3 fixture")
  }
  guard @fs.FileStore::new("\{base}/v3_u32_le_zstd.zarr") is Some(zstd_files) else {
    fail("compressed fixture")
  }
  let server = @client_http.Server(@socket.Addr::parse("127.0.0.1:0"))
  let fail_chunk = [false]
  @async.with_task_group() <| group => {
    group.spawn_bg(no_wait=true) <| () => {
      server.run_forever((request, _body, conn) => {
        let route = request.path[1:].to_owned()
        let (files, key) = if route.has_prefix("v2/") {
          (v2_files, route[3:].to_owned())
        } else if route.has_prefix("v3z/") {
          (zstd_files, route[4:].to_owned())
        } else if route.has_prefix("v3/") {
          (v3_files, route[3:].to_owned())
        } else {
          (v3_files, "")
        }
        if fail_chunk[0] && route == "v3/science/image/c/1" {
          conn.send_response(500, "Internal Server Error")
        } else {
          match files.get(key) {
            Some(bytes) => {
              conn.send_response(200, "OK")
              conn.write(bytes as &@io.Data)
            }
            None => conn.send_response(404, "Not Found")
          }
        }
      })
    }
    let root = "http://127.0.0.1:\{server.addr.port()}"
    let url = "\{root}/v3"
    guard @http.HttpStore::new(url) is Some(remote) else { fail("HTTP store") }
    guard remote.hydrate_region("science/image", [1], [2]) is Some(cache) else {
      fail("hydrate")
    }
    guard @array.open_u8(cache, "science/image") is Some(image) else {
      fail("typed array")
    }
    assert_eq(image.read_region([1], [2]), Some(b"\x05\x09"))
    guard @http.HttpStore::new("\{root}/v2") is Some(v2_remote) else {
      fail("v2 HTTP store")
    }
    guard v2_remote.hydrate_region("science/image", [1], [2]) is Some(v2_cache) else {
      fail("v2 hydrate")
    }
    guard @array.open_u8(v2_cache, "science/image") is Some(v2_image) else {
      fail("v2 typed array")
    }
    assert_eq(v2_image.read_region([1], [2]), Some(b"\x05\x09"))
    guard @http.HttpStore::new("\{root}/v3z") is Some(zstd_remote) else {
      fail("compressed HTTP store")
    }
    guard zstd_remote.hydrate_region("", [1], [2]) is Some(zstd_cache) else {
      fail("compressed hydration")
    }
    guard @array.open_u32(zstd_cache, "") is Some(values) else {
      fail("compressed typed array")
    }
    assert_eq(values.read_region([1], [2]), Some([4000000000U, 4294967294U]))
    guard @http.HttpStore::new(url, max_chunks=1) is Some(one_chunk) else {
      fail("one chunk limit")
    }
    assert_true(one_chunk.hydrate_region("science/image", [1], [2]) is None)
    guard @http.HttpStore::new(url, max_metadata_bytes=1) is Some(tiny_meta) else {
      fail("metadata limit")
    }
    assert_true(tiny_meta.hydrate_region("science/image", [1], [2]) is None)
    guard @http.HttpStore::new(url, max_chunk_bytes=1) is Some(tiny_chunk) else {
      fail("chunk limit")
    }
    assert_true(tiny_chunk.hydrate_region("science/image", [1], [2]) is None)
    fail_chunk[0] = true
    assert_true(remote.hydrate_region("science/image", [1], [2]) is None)
  }
}
