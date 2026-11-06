# Hierarchy discovery and remote diagnostics

Version **0.8.0** adds metadata-validated hierarchy discovery and structured remote errors. Existing HTTP/S3 `open_array` and `hydrate_region` methods still return `Option`; their new `_result` counterparts preserve the failure cause. Use MoonBit **0.10.20 or newer**.

## Discover datasets

The `hierarchy` package exposes `Node { path, kind, format }`, where `kind` is `ArrayNode` or `GroupNode`, and `format` is `metadata.V2` or `V3`. Paths are relative to the store; `""` is the root. Supported entry points:

| Backend | Immediate children | All descendants |
| --- | --- | --- |
| Memory | `hierarchy.list_children(store, path)` | `hierarchy.walk(store, path)` |
| Native files | `FileStore::list_children_result(path)` | `FileStore::walk_result(path)` |
| Native S3 | `S3Store::list_children_result(path)` | `S3Store::walk_result(path)` |

All return `Result[Array[Node], store.AccessError]`. Children are sorted lexically; traversal is deterministic breadth-first and excludes the starting group. It descends through **explicit metadata groups** only. Chunk directories, ordinary files and unmarked prefixes are ignored. Historical implicit groups are not inferred. V3 reserved `__` prefixes are skipped; legal v2 `__` names remain discoverable. A malformed/conflicting child metadata document fails the operation instead of silently removing that child from the result. Discovery reads metadata, not chunk data, and does not imply every discovered dtype/codec can be decoded.

Run the portable example:

```sh
moon run --target wasm-gc cmd/discovery_demo
moon run --target native cmd/discovery_demo
```

Expected: `Zarr discovery: 2 groups, 1 array; lexical breadth-first order and depth limit verified`.

For a native application, add `zlhahaha/zarr@0.8.0` and the direct `moonbitlang/async@0.20.3` dependency, declare `supported_targets = "native"`, and import `zlhahaha/zarr/store/fs` as `@fs` plus `moonbitlang/async`:

```moonbit
async fn main {
  guard @fs.FileStore::new("example.zarr") is Some(store) else {
    abort("invalid store path")
  }
  match store.walk_result("", max_nodes=1024, max_depth=16) {
    Ok(nodes) => for node in nodes { println(node.path) }
    Err(_) => abort("hierarchy is missing, invalid, unreadable or over budget")
  }
}
```

`example.zarr` must contain an explicit root group. Calling a listing method on an array yields `NotGroup`; an absent starting group yields `NotFound`. Native listing skips directory symlinks and honors the metadata namespace of a consolidated snapshot; it does not discover additional physical metadata outside that snapshot. Other existing filesystem APIs retain their documented I/O-exception behavior.

## Bound the work

Defaults are 4,096 returned nodes and traversal depth 64. Root depth is zero. `max_depth=0` succeeds only for an empty group. Caps fail with `LimitExceeded`, never a silently truncated tree. Walks buffer their returned descriptors and are not total-process memory or concurrent-writer snapshot guarantees.

- Memory `max_keys=65536` caps matching metadata keys; it scans the in-memory key map, without retaining raw chunk keys.
- Filesystem `max_entries=65536` caps examined directory entries or consolidated metadata keys per listing, including ignored files.
- S3 constructor options `listing_page_size=1000`, `max_listing_pages=32`, `max_listing_entries=16384` cap each group listing. Page size must be 1–1,000. Pages count both common prefixes and object entries. Every XML response obeys `ReadLimits.max_metadata_bytes` (1 MiB by default), XML depth 16 and 32,768 element nodes. Reduce page size for unusually long object keys.

S3 performs signed **ListObjectsV2**, with delimiter `/`, URL-encoded names, opaque continuation tokens, per-request timeouts and one transient retry. It rejects repeated tokens, malformed/unsupported XML, out-of-prefix entries and inconsistent counts. The restricted XML reader accepts standard unprefixed S3 response elements and the standard default namespace; it rejects DTDs, external entities and mixed-content extensions. It is not a general-purpose XML library.

The principal needs **`s3:ListBucket` as well as `s3:GetObject`**, scoped to the configured prefix. Ordinary HTTP has no generic directory-listing protocol: `HttpStore::open_node_result` can inspect a known path, but arbitrary HTTP directories are not enumerated. A real private MinIO regression forces two-entry pages and verifies nested groups, Unicode/spaces, pagination budgets and missing prefixes. See [REMOTE.md](REMOTE.md#reproduce-private-minio-integration).

## Diagnose remote failures

Import `zlhahaha/zarr/store` as `@store` to match `AccessError` variants. `HttpStore` and `S3Store` expose:

```moonbit
match remote.open_array_result("image") {
  Ok(metadata) => println(metadata.shape.length())
  Err(@store.NotFound(_)) => println("array metadata is absent")
  Err(@store.Authentication(_, status)) => println("access denied: \{status}")
  Err(@store.Timeout(_)) => println("request timed out after its retry")
  Err(@store.LimitExceeded(stage, _)) => println("read budget rejected: \{stage}")
  Err(_) => println("invalid metadata, HTTP response or transport failure")
}
```

| Variants | Meaning |
| --- | --- |
| `InvalidPath`, `InvalidRegion` | Noncanonical/invalid paths or invalid/overflowing selections |
| `NotFound`, `NotArray`, `NotGroup` | Metadata is absent or the node has the wrong kind |
| `Authentication(key, status)` | HTTP 401 or 403, not a missing chunk |
| `Timeout`, `Transport`, `HttpStatus` | Request timeout, connection/read failure, or another HTTP status |
| `Conflict` | HTTP 412 or a shard payload disappeared/changed after its index was read |
| `Protocol`, `InvalidShard` | Invalid Range/listing responses, inconsistent shard extents or invalid indexes |
| `InvalidMetadata`, `UnsupportedMetadata` | Malformed/conflicting metadata or an unsupported metadata transformation |
| `LimitExceeded`, `HeaderRejected`, `Io` | A budget failed, the header/signing callback declined, or discovery hit a filesystem error |

Contexts contain relative keys and controlled stage/reason strings; response bodies, credentials and signing headers are not included. No shared mutable “last error” is used. `AccessError::is_retryable()` recognizes transport/timeouts and HTTP 429/500/502/503/504. GETs already retry once; authentication, protocol, validation and budget failures are not retried. Failed discovery stops at the first failed object, so a timed-out first metadata probe makes two attempts rather than continuing through other marker names.

`hydrate_region_result` validates/downloads **encoded** metadata/chunk/shard bytes. It does not decode selected codec payloads. A missing ordinary chunk or whole shard remains a successful hydration using fill values; missing array metadata returns `NotFound`. Subsequent typed `array.read_region` decoding still returns `Option`. Legacy optional methods collapse structured failures to `None` and retain conventional path normalization; new result/discovery methods require canonical paths. Replacing an HTTP header provider starts a fresh cache to avoid reusing bytes from an earlier authorization context.
