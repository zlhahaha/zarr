///|
/// A key exists but exceeds its metadata or encoded-object input budget.
/// This must not be mistaken for a missing chunk and its fill value.
pub suberror ReadLimitExceeded {
  ReadLimitExceeded(String)
} derive(Debug)

///|
pub extend ReadLimitExceeded with Debug::{to_repr}

///|
pub fn FileStore::read_limits(self : FileStore) -> @store.ReadLimits {
  self.limits
}

///|
fn FileStore::scratch(self : FileStore) -> @store.MemoryStore {
  @store.MemoryStore::new(read_limits=self.limits)
}
