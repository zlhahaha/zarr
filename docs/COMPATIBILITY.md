# Format compatibility

| Capability | Zarr v2 | Zarr v3 |
| --- | --- | --- |
| Parse regular-grid array metadata | Yes, common string dtypes | Yes, common string data types |
| Metadata and chunk keys | `.` and `/` separators | default and v2-compatible encodings |
| Raw encoded chunk storage | Memory and native filesystem | Memory and native filesystem |
| Safe single-key filesystem replacement | Native: exclusive sibling staging + replace | Native: exclusive sibling staging + replace |
| `bool` element and slice I/O | Memory and native filesystem | Memory and native filesystem; bytes codec |
| `uint8` element and slice I/O | Memory and native filesystem; C/F order | Memory and native filesystem; bytes codec |
| `int8` element and slice I/O (`Int` API, range-checked) | Memory and native filesystem; C/F order | Memory and native filesystem; bytes codec |
| `uint16` element and slice I/O | Memory and native filesystem; little/big endian, C/F order | Memory and native filesystem; little/big endian bytes codec |
| `int16` element and slice I/O | Memory and native filesystem; little/big endian, C/F order | Memory and native filesystem; little/big endian bytes codec |
| `uint32` element and slice I/O | Memory and native filesystem; little/big endian, C/F order | Memory and native filesystem; little/big endian bytes codec |
| `float64` element I/O | Memory and native filesystem; little/big endian, C/F order | Memory and native filesystem; little/big endian bytes codec |
| `float32` element I/O | Memory and native filesystem; little/big endian, C/F order | Memory and native filesystem; little/big endian bytes codec |
| `int32` element I/O | Memory and native filesystem; little/big endian, C/F order | Memory and native filesystem; little/big endian bytes codec |
| `int64` element and slice I/O | Memory and native filesystem; little/big endian, C/F order | Memory and native filesystem; little/big endian bytes codec |
| `uint64` element and slice I/O | Memory and native filesystem; little/big endian, C/F order | Memory and native filesystem; little/big endian bytes codec |
| Rectangular slice I/O (all listed types) | Memory and native filesystem | Memory and native filesystem |
| Incremental N-D tile traversal | `chunk.RegionTileCursor`, caller reads each bounded tile | Same; no whole-result allocation by the cursor |
| gzip compression (levels 0–9) | Read/write | Read/write after bytes codec |
| zstd compression (levels 0–22) | Read/write | Read/write after bytes codec, with or without frame checksum |
| zlib compression (levels 0–9) | Read/write | Not a v3 core codec |
| Blosc1 frames (LZ4/LZ4HC/Zlib/Zstd; no, byte or bit shuffle) | LZ4 read/write; LZ4HC/Zlib/Zstd read-only; BloscLZ unsupported | LZ4 read/write after bytes codec; LZ4HC/Zlib/Zstd read-only; BloscLZ unsupported |
| Other dtypes, filters and codecs | Planned | Planned |
| Groups, ancestors and attributes | Memory and native filesystem (`.zgroup`/`.zattrs`) | Memory and native filesystem (`zarr.json`) |
| Consolidated metadata | Read-only native `.zmetadata` snapshot | Read-only native inline root `zarr.json` snapshot (zarr-python convention) |
| HTTP read-only regional hydration | Native, bounded metadata/chunk downloads | Native, bounded ordinary or shard-index/payload byte-range downloads |
| Sharding-indexed codec | Not a v2 codec | Native filesystem and HTTP/S3 reads; native whole-shard writes for uint8/uint16/float32; start/end index, index endian and optional CRC32C; no partial-shard or remote writes |
| S3-compatible object storage | Native, read-only regional hydration | Native, read-only ordinary/sharded regional hydration; anonymous or explicit SigV4 credentials |
| Explicit group children and breadth-first traversal | Memory, native filesystem (including consolidated snapshots), S3 | Same; signed S3 pagination, bounded nodes/depth/entries |
| Structured remote diagnostics | HTTP/S3 `_result` APIs; legacy optional APIs retained | Same; metadata, transport/authentication, budgets and shard/Range failures |

Float32/float64 fill values also support the standard JSON strings `"NaN"`, `"Infinity"`, and `"-Infinity"`. Creating an array with any NaN writes the canonical `"NaN"` fill value; v3 payload-specific hexadecimal NaN fills are not supported.

See [supported format limits](USAGE.md#supported-format-subset) and [interop coverage](INTEROPERABILITY.md).

## Specification and attribution

This project implements the publicly documented [Zarr v2 storage specification](https://zarr-specs.readthedocs.io/en/latest/v2/v2.0.html), [Zarr v3 core specification](https://zarr-specs.readthedocs.io/en/latest/v3/core/), and [sharding-indexed codec specification](https://zarr-specs.readthedocs.io/en/latest/v3/codecs/sharding-indexed/index.html). The [Zarr specifications repository](https://github.com/zarr-developers/zarr-specs) is CC BY 4.0. The Blosc codec follows the public [C-Blosc chunk-format description](https://github.com/Blosc/c-blosc/blob/main/README_CHUNK_FORMAT.rst) and [LZ4 block format](https://github.com/lz4/lz4/blob/dev/doc/lz4_Block_format.md) (the reference projects have BSD-style licenses); no upstream implementation code was copied. The committed interoperability stores were generated by this repository's original scripts using [zarr-python 3.4.0](https://github.com/zarr-developers/zarr-python), which is MIT-licensed; see [../integration/fixtures/zarr-python/README.md](../integration/fixtures/zarr-python/README.md). Compression uses the Apache-2.0 MoonBit dependencies [moonbit-community/flate](https://mooncakes.io/docs/moonbit-community/flate) and [Milky2018/zstd](https://mooncakes.io/docs/Milky2018/zstd); S3 SigV4 uses [moonbitlang/x](https://mooncakes.io/docs/moonbitlang/x) SHA-256/HMAC and UTC conversion. The optional real-data example reads the publicly documented [OME-Zarr OpenSciVis dataset](https://github.com/InsightSoftwareConsortium/OMEZarrOpenSciVisDatasets) without distributing its bytes in this repository.

This project is licensed under Apache-2.0; see [LICENSE](../LICENSE).
