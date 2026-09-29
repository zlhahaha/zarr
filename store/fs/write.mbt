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
priv struct StagedWrite {
  path : String
  file : @async_fs.File
  mut closed : Bool
}

///|
fn StagedWrite::close(self : StagedWrite) -> Unit {
  if !self.closed {
    self.file.close()
    self.closed = true
  }
}

///|
fn next_write_name() -> String {
  ".zarr-tmp-\{write_name_source.uint64().to_string(radix=16)}"
}

///|
async fn create_write_temp(
  parent : String,
  candidate : () -> String,
) -> StagedWrite {
  for _ in 0..<128 {
    let temporary = "\{parent}/\{candidate()}"
    // The caller shields this whole acquisition/ownership-registration scope.
    // Never truncate a collision or remove a path we did not exclusively create.
    try
      @async_fs.open(
        temporary,
        mode=@async_fs.WriteOnly,
        create_mode=@async_fs.CreateNew,
        sync=@async_fs.Data,
      )
    catch {
      @os_error.OSError(_) as err if err.is_EEXIST() => ()
      err => raise err
    } noraise {
      file => return { path: temporary, file, closed: false, }
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
  staged : StagedWrite,
  value : Bytes,
  stage : async (@async_fs.File, Bytes) -> Unit,
) -> Unit {
  defer staged.close()
  // Even an empty value must observe cancellation deferred by acquisition
  // before entering commit; its write might otherwise perform no async I/O.
  @async.pause()
  stage(staged.file, value)
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
  let owned : Ref[StagedWrite?] = Ref(None)
  // Unlike an ordinary catch handler, errdefer also handles cancellation.
  // Forced termination can still leave an orphan; remove only our own temp.
  errdefer @async.protect_from_cancel(
    () => {
      if owned.val is Some(staged) {
        staged.close()
        cleanup(staged.path) catch {
          cleanup_error =>
            raise WriteCleanupFailed(staged.path, cleanup_error.to_string())
        }
      }
    },
    resume_on_cancel=true,
  )
  // Register ownership inside the shield, before crossing any unprotected
  // async return boundary. Cleanup is already installed if that boundary cancels.
  let staged = @async.protect_from_cancel(
    () => {
      let acquired = create_write_temp(parent, candidate)
      owned.val = Some(acquired)
      acquired
    },
    resume_on_cancel=true,
  )
  close_after_stage(staged, value, stage)
  // A rename already dispatched to the OS must finish with a known outcome.
  // Successful replacement is not rolled back if cancellation arrives here.
  @async.protect_from_cancel(
    () => commit(staged.path, destination),
    resume_on_cancel=true,
  )
}
