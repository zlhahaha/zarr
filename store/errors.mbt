///|
/// Structured failures for remote reads and hierarchy discovery. Context is
/// a store-relative key or controlled stage name, never credential headers.
#derive(Eq, Debug)
pub(all) enum AccessError {
  InvalidPath(String)
  NotFound(String)
  NotGroup(String)
  NotArray(String)
  InvalidMetadata(String)
  UnsupportedMetadata(String)
  InvalidRegion(String)
  InvalidShard(String)
  LimitExceeded(String, String)
  Authentication(String, Int32)
  HttpStatus(String, Int32)
  Transport(String)
  Timeout(String)
  Conflict(String)
  Protocol(String, String)
  HeaderRejected(String)
  Io(String)
}

///|
pub extend AccessError with Eq::{equal, not_equal}

///|
pub extend AccessError with Debug::{to_repr}

///|
pub fn AccessError::is_retryable(self : AccessError) -> Bool {
  match self {
    Transport(_) | Timeout(_) | HttpStatus(_, 429 | 500 | 502 | 503 | 504) =>
      true
    _ => false
  }
}
