///|
async test "staged partial write failure preserves existing and absent targets" {
  let dir = @async_fs.tmpdir(prefix="zarr-write-stage")
  for existing in [false, true] {
    let target = "\{dir}/value"
    if existing {
      @async_fs.write_file(target, b"old", create_mode=@async_fs.CreateNew)
    }
    let committed = Ref(false)
    let failed = try {
      put_file_safely(
        target,
        dir,
        b"replacement",
        candidate=() => ".zarr-tmp-partial",
        stage=(file, _) => {
          file.write(b"partial"[:])
          raise Failure("injected partial-write failure")
        },
        commit=(_, _) => committed.val = true,
      )
      false
    } catch {
      Failure(message) => message == "injected partial-write failure"
      _ => false
    }
    assert_true(failed)
    assert_true(!committed.val)
    assert_true(!@async_fs.exists("\{dir}/.zarr-tmp-partial"))
    guard FileStore::new(dir) is Some(store) else { fail("store") }
    assert_eq(store.get("value"), if existing { Some(b"old") } else { None })
  }
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "commit failure closes staging handle and keeps destination intact" {
  let dir = @async_fs.tmpdir(prefix="zarr-write-commit")
  let staged_handle : Ref[@async_fs.File?] = Ref(None)
  for existing in [false, true] {
    let target = "\{dir}/value"
    if existing {
      @async_fs.write_file(target, b"old", create_mode=@async_fs.CreateNew)
    }
    let failed = try {
      put_file_safely(
        target,
        dir,
        b"complete replacement",
        candidate=() => ".zarr-tmp-commit",
        stage=(file, value) => {
          staged_handle.val = Some(file)
          write_staged(file, value)
        },
        commit=(temporary, _) => {
          guard staged_handle.val is Some(file) else { fail("handle") }
          let closed = try {
            file.size() |> ignore
            false
          } catch {
            _ => true
          }
          assert_true(closed)
          guard FileStore::new(dir) is Some(store) else { fail("store") }
          assert_eq(
            store.get(".zarr-tmp-commit"),
            Some(b"complete replacement"),
          )
          assert_true(@async_fs.exists(temporary))
          raise Failure("injected replacement failure")
        },
      )
      false
    } catch {
      Failure(message) => message == "injected replacement failure"
      _ => false
    }
    assert_true(failed)
    assert_true(!@async_fs.exists("\{dir}/.zarr-tmp-commit"))
    guard FileStore::new(dir) is Some(store) else { fail("store") }
    assert_eq(store.get("value"), if existing { Some(b"old") } else { None })
  }
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "exclusive staging retries collisions without touching foreign data" {
  let dir = @async_fs.tmpdir(prefix="zarr-write-collision")
  @async_fs.write_file(
    "\{dir}/.zarr-tmp-occupied",
    b"foreign",
    create_mode=@async_fs.CreateNew,
  )
  let attempts = Ref(0)
  put_file_safely("\{dir}/value", dir, b"new", candidate=() => {
    attempts.val += 1
    if attempts.val == 1 {
      ".zarr-tmp-occupied"
    } else {
      ".zarr-tmp-owned"
    }
  })
  assert_eq(attempts.val, 2)
  guard FileStore::new(dir) is Some(store) else { fail("store") }
  assert_eq(store.get("value"), Some(b"new"))
  assert_eq(store.get(".zarr-tmp-occupied"), Some(b"foreign"))
  assert_true(!@async_fs.exists("\{dir}/.zarr-tmp-owned"))
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "collision exhaustion is bounded and does not truncate or clean foreign files" {
  let dir = @async_fs.tmpdir(prefix="zarr-write-exhaustion")
  @async_fs.write_file("\{dir}/value", b"old", create_mode=@async_fs.CreateNew)
  @async_fs.write_file(
    "\{dir}/.zarr-tmp-fixed",
    b"foreign",
    create_mode=@async_fs.CreateNew,
  )
  let attempts = Ref(0)
  let failed = try {
    put_file_safely("\{dir}/value", dir, b"new", candidate=() => {
      attempts.val += 1
      ".zarr-tmp-fixed"
    })
    false
  } catch {
    Failure(_) => true
    _ => false
  }
  assert_true(failed)
  assert_eq(attempts.val, 128)
  guard FileStore::new(dir) is Some(store) else { fail("store") }
  assert_eq(store.get("value"), Some(b"old"))
  assert_eq(store.get(".zarr-tmp-fixed"), Some(b"foreign"))
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "staging creation error never removes a foreign directory" {
  let dir = @async_fs.tmpdir(prefix="zarr-write-create")
  @async_fs.mkdir("\{dir}/.zarr-tmp-directory")
  let reached_stage = Ref(false)
  let failed = try {
    put_file_safely(
      "\{dir}/value",
      dir,
      b"new",
      candidate=() => ".zarr-tmp-directory/absent/file",
      stage=(_, _) => reached_stage.val = true,
    )
    false
  } catch {
    _ => true
  }
  assert_true(failed)
  assert_true(!reached_stage.val)
  assert_true(@async_fs.exists("\{dir}/.zarr-tmp-directory"))
  assert_true(!@async_fs.exists("\{dir}/value"))
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "cleanup failure reports owned path and does not hide orphan or alter old value" {
  let dir = @async_fs.tmpdir(prefix="zarr-write-cleanup")
  @async_fs.write_file("\{dir}/value", b"old", create_mode=@async_fs.CreateNew)
  let reported = try {
    put_file_safely(
      "\{dir}/value",
      dir,
      b"new",
      candidate=() => ".zarr-tmp-cleanup",
      stage=(file, _) => {
        file.write(b"partial"[:])
        raise Failure("write failed")
      },
      cleanup=_ => raise Failure("cleanup failed"),
    )
    false
  } catch {
    WriteCleanupFailed(path, diagnostic) =>
      path == "\{dir}/.zarr-tmp-cleanup" &&
      diagnostic.contains("cleanup failed")
    _ => false
  }
  assert_true(reported)
  guard FileStore::new(dir) is Some(store) else { fail("store") }
  assert_eq(store.get("value"), Some(b"old"))
  assert_eq(store.get(".zarr-tmp-cleanup"), Some(b"partial"))
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "cooperative cancellation closes and removes partial stage preserving old target" {
  let dir = @async_fs.tmpdir(prefix="zarr-write-cancel")
  @async_fs.write_file("\{dir}/value", b"old", create_mode=@async_fs.CreateNew)
  let entered = Ref(false)
  let cleanup_ran = Ref(false)
  let committed = Ref(false)
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      put_file_safely(
        "\{dir}/value",
        dir,
        b"new",
        candidate=() => ".zarr-tmp-cancel",
        stage=(file, _) => {
          file.write(b"partial"[:])
          entered.val = true
          @async.sleep(10000)
        },
        commit=(_, _) => committed.val = true,
        cleanup=path => {
          @async.pause()
          remove_staged(path)
          cleanup_ran.val = true
        },
      )
    })
    while !entered.val {
      @async.pause()
      // Normal group exit cancels its unfinished no_wait child and waits for cleanup.
    }
  })
  assert_true(cleanup_ran.val)
  assert_true(!committed.val)
  assert_true(!@async_fs.exists("\{dir}/.zarr-tmp-cancel"))
  guard FileStore::new(dir) is Some(store) else { fail("store") }
  assert_eq(store.get("value"), Some(b"old"))
  @async_fs.rmdir(dir, recursive=true)
}

///|
async test "cancellation during protected commit completes replacement without rollback" {
  let dir = @async_fs.tmpdir(prefix="zarr-write-cancel-commit")
  @async_fs.write_file("\{dir}/value", b"old", create_mode=@async_fs.CreateNew)
  let entered = Ref(false)
  let release = Ref(false)
  let completed = Ref(false)
  @async.with_task_group(group => {
    let task = group.spawn(no_wait=true, () => {
      put_file_safely(
        "\{dir}/value",
        dir,
        b"new",
        candidate=() => ".zarr-tmp-commit-cancel",
        commit=(temporary, destination) => {
          entered.val = true
          while !release.val {
            @async.pause()
          }
          replace_staged(temporary, destination)
        },
      )
      completed.val = true
    })
    while !entered.val {
      @async.pause()
    }
    task.cancel()
    release.val = true
  })
  assert_true(completed.val)
  assert_true(!@async_fs.exists("\{dir}/.zarr-tmp-commit-cancel"))
  guard FileStore::new(dir) is Some(store) else { fail("store") }
  assert_eq(store.get("value"), Some(b"new"))
  @async_fs.rmdir(dir, recursive=true)
}
