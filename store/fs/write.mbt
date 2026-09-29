///|
/// Both the operation and cleanup failed. Fields are the owned temporary path
/// and cleanup failure diagnostic; this error supersedes the original failure.
/// The destination is never deleted as a fallback.
pub suberror WriteCleanupFailed {
  WriteCleanupFailed(String, String)
} derive(Debug)

///|
pub extend WriteCleanupFailed with Debug::{to_repr}

///|
let write_name_source : @random.Rand = @random.Rand::new()

///|
fn next_write_name() -> String {
  ".zarr-tmp-\{write_name_source.uint64().to_string(radix=16)}"
}

///|
async fn create_write_temp(
  parent : String,
  candidate : () -> String,
) -> (String, @async_fs.File) {
  for _ in 0..<128 {
    let temporary = "\{parent}/\{candidate()}"
    // Finish acquisition before observing cancellation so the caller always
    // owns the returned handle/path and can close/remove it. Never truncate a
    // collision or remove a path for which exclusive creation failed.
    try
      @async.protect_from_cancel(
        () => {
          @async_fs.open(
            temporary,
            mode=@async_fs.WriteOnly,
            create_mode=@async_fs.CreateNew,
            sync=@async_fs.Data,
          )
        },
        resume_on_cancel=true,
      )
    catch {
      @os_error.OSError(_) as err if err.is_EEXIST() => ()
      err => raise err
    } noraise {
      file => return (temporary, file)
    }
  }
  raise Failure::Failure(
    "Zarr temporary-file name collisions exceeded 128 attempts",
  )
}

///|
async fn write_staged(file : @async_fs.File, value : Bytes) -> Unit {
  file.write(value[:])
}

///|
async fn close_after_stage(
  file : @async_fs.File,
  value : Bytes,
  stage : async (@async_fs.File, Bytes) -> Unit,
) -> Unit {
  defer file.close()
  stage(file, value)
}

///|
async fn replace_staged(temporary : String, destination : String) -> Unit {
  @async_fs.rename(temporary, destination, replace=true)
}

///|
async fn remove_staged(temporary : String) -> Unit {
  @async_fs.remove(temporary) catch {
    @os_error.OSError(_) as err if err.is_ENOENT() => ()
    err => raise err
  }
}

///|
// Private operation seams let whitebox tests inject partial writes, commit
// failures, cancellation and cleanup failures in the actual production path.
async fn put_file_safely(
  destination : String,
  parent : String,
  value : Bytes,
  candidate? : () -> String = next_write_name,
  stage? : async (@async_fs.File, Bytes) -> Unit = write_staged,
  commit? : async (String, String) -> Unit = replace_staged,
  cleanup? : async (String) -> Unit = remove_staged,
) -> Unit {
  let (temporary, file) = create_write_temp(parent, candidate)
  // Unlike an ordinary catch handler, errdefer also handles cancellation.
  // Forced termination can still leave an orphan; remove only our own temp.
  errdefer (@async.protect_from_cancel(
    () => cleanup(temporary),
    resume_on_cancel=true,
  ) catch {
    cleanup_error =>
      raise WriteCleanupFailed(temporary, cleanup_error.to_string())
  })
  close_after_stage(file, value, stage)
  // A rename already dispatched to the OS must finish with a known outcome.
  // Successful replacement is not rolled back if cancellation arrives here.
  @async.protect_from_cancel(
    () => commit(temporary, destination),
    resume_on_cancel=true,
  )
}
