# Tiled and remote Zarr reads

Version `0.7.0` adds an incremental N-dimensional tile planner and native, read-only HTTP/S3 hydration of ordinary and supported Zarr v3 sharded arrays. The same typed `read_region` methods decode every downloaded tile. These APIs do not perform remote writes or automatically expose a streaming typed array.

## Process a large logical rectangle in bounded tiles

`chunk.RegionTileCursor::new(shape, origin, extent, tile_shape, max_tile_elements=...)` validates bounds without computing or allocating the full region. Each `next()` yields a C-order `RegionTile { origin, extent }`. Pass each tile to the appropriate typed `read_region`; process/discard its result before advancing. Tile shapes need not align with chunk boundaries, although alignment usually avoids redundant decode work. An empty selection yields no tiles and a rank-zero scalar yields one tile.

The cursor limits **one tile's elements**, not its bytes or total process memory. Choose `tile_shape` and `max_tile_elements` so that each typed read also satisfies `store.ReadLimits` for bytes, decoded chunk size and touched chunks. The typed result and temporary decoded chunks are still allocated. Holding prior tile results, a large cache or concurrent reads can increase aggregate memory. The cursor does not make writes transactional.

Reproduce a full logical 256 MiB scan without allowing a 256 MiB `read_region` allocation:

```sh
moon run --target native cmd/tile_demo
```

Expected output: `Zarr tiled scan: 256 MiB logical array, 256 tiles, checksum=268435456`. The sample is a sparsely filled in-memory array; the library reads 256 successive 1 MiB tiles. The ordinary whole-region call is first checked to fail under default limits. This is a correctness/resource-budget demonstration, **not** a measured peak-RSS result or a benchmark on 256 MiB of encoded file data.

## Read a public real dataset from S3

The optional `cmd/real_bonsai` example reads the public [OME-Zarr OpenSciVis](https://github.com/InsightSoftwareConsortium/OMEZarrOpenSciVisDatasets) 3D microscopy array `s3://ome-zarr-scivis/v0.4/64x0/bonsai.ome.zarr/scale0/bonsai`. Its v2 metadata declares shape `[256,256,256]`, chunks `[64,64,64]`, `uint8`, `/` chunk keys and Zstd compression. The example discovers metadata through `S3Store::open_array`, plans eight `[4,4,4]` tiles, hydrates and decodes one at a time, then checks 512 voxels, checksum `20736` and first value `40`:

```sh
moon run --target native cmd/real_bonsai
```

Expected output: `OME-Zarr bonsai: 8 bounded tiles, 512 real voxels, checksum=20736, first=40`. This makes eight small *logical* tile reads but the first request downloads a whole compressed ordinary chunk; successful encoded object responses are cached by the HTTP reader within its cap. It is an opt-in live-network example, not a CI gate or a full-dataset performance claim.

For a complete multi-object regional task, run:

```sh
moon run --target native cmd/real_bonsai --volume
```

This scans the `[0:128,0:128,0:128]` volume through eight aligned `[64,64,64]` tiles, each at most 262,144 decoded bytes. Expected output: `OME-Zarr bonsai: 8 bounded tiles, 2097152 real voxels, checksum=24039966, first=40`. Independent Python/numcodecs Zstd decoding of all eight objects reproduced the count and sum. A Windows native run on 2026-09-30 sampled the process working set every 100 ms and observed a maximum of **11,370,496 bytes (10.84 MiB)**; this is one host/run with eight cached compressed objects, not a portable peak-memory bound or throughput benchmark. The upstream dataset has at least one object outside this ROI whose bytes do not match its declared Zstd codec (Python decoding also fails); **do not infer that the entire 256³ dataset was validated**.

The checksum was independently reproduced by downloading only the `0/0/0` encoded chunk, decompressing with the `zstd` CLI and summing its `[0:8,0:8,0:8]` C-order voxels. If Python 3 and `zstd` are installed, this one-shot command verifies it without saving data:

```sh
python -c "import urllib.request,subprocess; u='https://ome-zarr-scivis.s3.us-east-1.amazonaws.com/v0.4/64x0/bonsai.ome.zarr/scale0/bonsai/0/0/0'; b=urllib.request.urlopen(u,timeout=20).read(); x=subprocess.run(['zstd','-d','--stdout'],input=b,capture_output=True,check=True).stdout; print(len(x),sum(x[(i*64+j)*64+k] for i in range(8) for j in range(8) for k in range(8)),x[0])"
```

Expected values: `262144 20736 40`. Live data and availability are maintained by its publisher, not by this library. This dataset exercises v2 ordinary chunks, not v3 sharding; independent local-server tests exercise Python-generated start/end-index shard layouts for HTTP/S3.

## Native S3-compatible adapter

Import `zlhahaha/zarr/store/s3` as `@s3`, `zlhahaha/zarr/array` as `@array`, and `moonbitlang/async` directly in your native executable package. After `moon add zlhahaha/zarr@0.7.0`, also run `moon add moonbitlang/async@0.20.3` because your package imports it directly.

```moonbit
guard @s3.S3Store::new(
    "ome-zarr-scivis",
    "us-east-1",
    prefix="v0.4/64x0/bonsai.ome.zarr",
  ) is Some(remote) else {
  abort("invalid S3 configuration")
}
guard remote.open_array("scale0/bonsai") is Some(metadata) else {
  abort("metadata unavailable or unsupported")
}
guard remote.hydrate_region("scale0/bonsai", [0, 0, 0], [4, 4, 4])
  is Some(cache) else {
  abort("remote read failed")
}
guard @array.open_u8(cache, "scale0/bonsai") is Some(image) else {
  abort("dtype or codec unsupported")
}
guard image.read_region([0, 0, 0], [4, 4, 4]) is Some(values) else {
  abort("decode failed")
}
```

For private buckets, construct `@s3.Credentials::new(access_key, secret_key, session_token=...)` from secrets supplied by your application, then pass `credentials=creds` to `S3Store::new`. Do not commit keys to source or print the credentials. This API does **not** search environment variables, assume an AWS profile, refresh expired session tokens or assume an instance-role provider. Recreate the store when credentials rotate. `endpoint="http://127.0.0.1:9000"` selects a path-style S3-compatible endpoint for local testing; use HTTPS for credentials outside a trusted local test environment. AWS regional default addresses are path-style and target general-purpose buckets; directory buckets and special endpoint types are not supported.

`HttpStore::open_array` and `S3Store::open_array` return validated metadata without downloading chunks. For v3 shards, `chunk_shape` describes the independently readable *inner* chunks, matching native `FileStore::open_array`. `hydrate_region` returns a temporary `MemoryStore`: when source data is sharded, its metadata is transformed into an ordinary inner-chunk view so existing typed APIs can decode selected chunks. It is **not** a faithful copy of the original sharded Zarr metadata and must not be uploaded as a replacement for the source. Mutating the returned memory store does not write remotely.

## Range requests, errors and limits

For v3 sharding-indexed arrays, HTTP/S3 downloads the fixed-size index at the beginning or end of each selected shard and only the encoded inner-chunk byte ranges needed by the selection. It validates `206 Partial Content`, exact `Content-Range` and body lengths, index size/CRC32C, entry bounds and `If-Match` against the index response ETag when available. A server that ignores Range, a changed ETag (`412`), malformed shard, unsupported codec or truncated response fails the hydration; it does not silently use a fill value. A missing shard/ordinary chunk (`404`) yields the Zarr fill value. S3 can return `403` for an absent key if the principal lacks `ListBucket`, so `403` is **never** treated as a missing chunk.

Default caps remain 1 MiB metadata, 64 MiB encoded/decoded chunk and logical region bytes, 8,388,608 region elements and 16,384 touched chunks through `ReadLimits`. HTTP/S3 additionally defaults to at most 1,024 touched chunks and 64 MiB cumulative encoded hydration bytes; shard index and payload bytes both count. `request_timeout_ms` defaults to 30,000 **per HTTP request**. GETs retry once after 50 ms only for transport failures, timeout, `429` and selected `5xx` responses; `403`, `412`, malformed Range and decode failures are not retried. There is no total-operation deadline or aggregate-RAM bound.

Both remote adapters currently return `None` for transport, authentication, protocol, budget and decode failures; they do not yet expose a structured error type. A whole multi-chunk read is not a stable snapshot if objects change during the call, especially when ETags are absent. No object listing, write, presigned-query URL, CDN-specific behavior, bucket-region auto-discovery, credential-chain resolution or private AWS/MinIO end-to-end integration is claimed. The SigV4 signer passes AWS's published [GET Range test vector](https://docs.aws.amazon.com/AmazonS3/latest/developerguide/sig-v4-header-based-auth.html), local signed-request tests pass, and a public anonymous AWS object was read live; these are the verified boundaries of this early adapter.
