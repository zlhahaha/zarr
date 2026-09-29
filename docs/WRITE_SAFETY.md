# Filesystem single-key write safety

Version `0.5.0` changes the native `FileStore::put` implementation. It also protects every ordinary chunk, array/group metadata and attributes written through that method. No caller opt-in or signature change is required. Memory stores are unchanged; HTTP/consolidated views remain read-only and sharded writes remain unsupported.

## Replacement protocol

1. Validate the logical key and create missing parent directories. Read-only/invalid keys return `false` before staging.
2. Exclusively create a randomized `.zarr-tmp-*` file in the target's directory using `CreateNew`. Retry only name collisions, up to 128 attempts. Never truncate or remove a pre-existing collision.
3. Write the complete byte value with async filesystem `Data` synchronization and close the staging handle, including on write failure/cancellation.
4. Rename the closed staging file onto the target with `replace=true`. Never delete the destination to make replacement succeed.
5. On failure before replacement, close the handle and remove only the owned staging path. `errdefer` registers cleanup, and cleanup is protected from cooperative cancellation.

Acquisition is protected until the returned handle/path can be owned; a pending cancellation is then observed by the staging work. Commit is protected until rename has a known outcome. A cancellation arriving during commit may therefore leave a complete new key, and `put` may return `true`; a later unprotected caller operation can observe that cancellation. Do not interpret cancellation as rollback.

The intended visibility is one complete old or new file for readers that open one key on a filesystem supporting atomic same-directory replacement. Linux/macOS/Windows native CI runs the same regressions, including a reader that keeps an old handle across replacement. This is not an unconditional guarantee for network filesystems, unusual mounts, older Windows rename fallbacks or a directory tree modified by other processes. Already-open handles can continue to reference the old file. An arbitrary external writer truncating a target in place is not protected by this library.

## Outcomes and recovery

| Outcome | Destination | Owned staging file | Caller result |
| --- | --- | --- | --- |
| Invalid key or read-only view | Unchanged | Not created | `false` |
| Parent/temporary creation fails | Not changed by this call | No acquired staging file | Exception; bounded collision exhaustion raises `Failure` |
| Stage write or replacement fails | Previous file unchanged, or absent for a new key | Removed if cleanup succeeds | Original exception |
| Cooperative cancellation before commit | Not replaced by this call | Closed and removed if cleanup succeeds | Cancellation propagates |
| Replacement succeeds | Complete new bytes | Moved to destination; no leftover | `true`, including possible cancellation during protected commit |
| Failure/cancellation followed by cleanup failure | Not replaced by this call | May remain | `fs.WriteCleanupFailed(path, diagnostic)` supersedes original error |
| Process killed or machine loses power | No crash-recovery promise | May remain | No reliable return value |

"Unchanged" assumes no independent writer changes the same target; this method does not restore an old value over a concurrent writer's successful commit. It also never removes parent directories created before a failed write.

After `WriteCleanupFailed`, stop writers, inspect the reported exact path and remove that owned staging file only when it is no longer in use. Do not rename partial staging bytes onto the destination. For a forced termination, stale `.zarr-tmp-*` files require manual inspection after all writers have stopped; the library does not sweep by prefix or age because another writer may still own such a file. Do not delete an entire store to recover a staging failure.

## Scope and compatibility

- This is **one-key replacement**, not a multi-chunk or multi-metadata-key transaction. Earlier completed keys remain after a later failure, and readers across keys can see mixed revisions. Group creation and v2 metadata/attributes involve multiple keys.
- There is no read-modify-write lock: two typed writers can each read an old chunk and replace it with different updates; the last successful complete replacement wins and an update can be lost. Serialize such writers externally.
- Data synchronization retains the previous filesystem write helper's intent, but the containing directory is not synchronized. Rename visibility and power-loss durability are different; no fsync-based whole-operation crash guarantee is claimed.
- Replacement creates a new file identity. Existing hard links/open handles can retain the old bytes; custom mode bits, ACLs, ownership and other metadata are not copied. Staging uses the dependency's default creation permissions (subject to the OS/umask). A symlink at the destination is replaced as a directory entry, not followed to update its target. Parent symlinks are still followed: this store is not a filesystem sandbox.
- The parent directory must allow temporary creation and rename/removal, not merely allow writing an existing file. Insufficient space/permissions or OS file-sharing restrictions can raise exceptions. An old file and the new encoded value can coexist until replacement, requiring extra disk space.
- Private fault-injection hooks exist only for whitebox tests, not as public configuration. These tests simulate partial writes/commit/cleanup failures and cooperative cancellation, not real disk exhaustion, hard power cuts, exhaustive races or all filesystem implementations.

## Reproduce

From the GitHub checkout, with `moonc >= 0.10.14` and native-backend support:

```sh
moon update
moon test --target native --deny-warn -p zlhahaha/zarr/store/fs
moon run --target native cmd/native_demo
moon test --target native --deny-warn
moon test --target wasm-gc --deny-warn
```

`cmd/native_demo` creates a compressed v3 array, writes initial values, overwrites the existing chunks, reopens/verifies the values and removes its temporary store. `store/fs/write_wbtest.mbt` injects deterministic failures/cancellation into the production helper. `store/fs/write_test.mbt` exercises the public API against the real filesystem, including rename rejection and concurrent complete-key replacement. All native CI platforms execute both suites; wasm-gc tests cover portable packages, not native filesystem operations.

Read benchmarks remain separately documented in [BENCHMARKS.md](BENCHMARKS.md). No new write-throughput or crash-durability measurements are claimed for this milestone.
