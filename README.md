# Zarr for MoonBit

[![CI](https://github.com/zlhahaha/zarr/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/zlhahaha/zarr/actions/workflows/ci.yml)
[![Mooncakes](https://img.shields.io/badge/Mooncakes-0.10.1-blue)](https://mooncakes.io/docs/zlhahaha/zarr)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)

Read and write chunked N-dimensional arrays in MoonBit using the Zarr v2 and
v3 storage formats. Load a region of a large array, process it tile by tile,
and exchange the results with zarr-python.

## Features

- **Typed array I/O.** Create arrays and read or write rectangular regions in
  memory or on a native filesystem. Supports booleans, integers, floats, and
  missing-chunk fill values.
- **Remote reads.** Fetch the chunks needed for a region over HTTP or
  S3-compatible storage. Typed tile readers support bounded, sequential scans.
- **Compression and sharding.** Read and write gzip and Zstd chunks. Read
  supported v3 shards and create or replace complete shards on native
  filesystems with `uint8`, `uint16`, or `float32` data.
- **Groups and metadata.** Discover hierarchies, read and write local
  attributes, and open supported consolidated metadata.

See the [format compatibility matrix](docs/COMPATIBILITY.md) for supported
layouts, codecs and backends. In-memory arrays work on Native and Wasm-GC.
Filesystem, HTTP and S3 require Native. HTTP and S3 access is read-only.

## Installation

Requires `moonc >= 0.10.20`. From your MoonBit project:

```sh
moon add zlhahaha/zarr@0.10.1
```

## Quick start

This example writes three values across a chunk boundary and reads the entire
four-element array back, including its fill value.

Set up an executable package with this `moon.pkg`:

```moonbit
import {
  "zlhahaha/zarr/array",
  "zlhahaha/zarr/metadata",
  "zlhahaha/zarr/store",
}

pkgtype(kind: "executable")
```

In `main.mbt`:

```moonbit
fn main {
  let store = @store.MemoryStore::new()
  guard @array.create_u8(store, @metadata.V3, "samples", [4], [2], b'\x00')
    is Some(samples) else { abort("could not create the array") }
  guard samples.write_region([1], [3], b"\x07\x09\x0b") else {
    abort("could not write the region")
  }
  guard samples.read_region([0], [4]) is Some(values) else {
    abort("could not read the region")
  }
  let numbers = values.to_array().map(byte => byte.to_int().to_string())
  println("[\{numbers.join(", ")}]")
}
```

Run `moon run --target wasm-gc .` from the executable package. It prints
`[0, 7, 9, 11]`. For a persistent array, see the
[native filesystem quickstart](docs/USAGE.md#native-array-example).

## Documentation

| Topic | Guide |
| --- | --- |
| Installation, package APIs and error handling | [Usage](docs/USAGE.md) |
| HTTP, S3 and bounded tile scans | [Remote access](docs/REMOTE.md) · [Typed readers](docs/SCANNING.md) |
| Complete-shard writes and storage guarantees | [Shard writes](docs/SHARD_WRITES.md) · [Write safety](docs/WRITE_SAFETY.md) |
| Python compatibility and performance | [Interoperability](docs/INTEROPERABILITY.md) · [Benchmarks](docs/BENCHMARKS.md) · [CT comparison](docs/VOLUME_COMPARISON.md) |
| Real-data examples | [CT crop and conversion](docs/REAL_VOLUME_PIPELINE.md) · [NumPy input batch](examples/zarr_npy_roi/README.md) |
| Building and testing from source | [Maintenance](docs/MAINTENANCE.md) |

## License

[Apache-2.0](LICENSE). This is an independent implementation of the Zarr
specifications. See [specification and attribution](docs/COMPATIBILITY.md#specification-and-attribution).
