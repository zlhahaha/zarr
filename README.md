# Zarr

A MoonBit implementation of the Zarr v2 and v3 storage formats for chunked N-dimensional arrays. This is an independent implementation, not an official Zarr Developers project.

## Status

Early development. The library can read and write uncompressed `uint8` and `float64` arrays in memory, including element access, rectangular slices, missing-chunk fill values and edge chunks. On the native backend, a filesystem store persists v2/v3 metadata and raw chunks, with `uint8` and `float64` element I/O. Groups and attributes can be read and written for both formats. Other dtypes/codecs, filesystem slicing and cloud access are not implemented yet. Do not use it as a general Zarr reader/writer yet.

| Capability | Zarr v2 | Zarr v3 |
| --- | --- | --- |
| Parse regular-grid array metadata | Yes, common string dtypes | Yes, common string data types |
| Metadata and chunk keys | `.` and `/` separators | default and v2-compatible encodings |
| Raw encoded chunk storage | Memory and native filesystem | Memory and native filesystem |
| Uncompressed `uint8` element I/O | Memory and native filesystem; C/F order | Memory and native filesystem; bytes codec |
| Uncompressed `float64` element I/O | Memory and native filesystem; little/big endian, C/F order | Memory and native filesystem; little/big endian bytes codec |
| Rectangular slice I/O (`uint8`, `float64`) | In-memory | In-memory |
| Other dtypes and compressed codecs | Planned | Planned |
| Groups and attributes | Memory and native filesystem (`.zgroup`/`.zattrs`) | Memory and native filesystem (`zarr.json`) |
| Cloud stores | Planned | Planned |

## Build and run

Requires the MoonBit toolchain. From this directory:

```sh
moon check --deny-warn
moon build
moon test --deny-warn
moon run cmd/main
moon test --target native --deny-warn
```

The example creates a v3 `uint8` array and writes a slice across chunks. It prints `Zarr v3 uint8 values: 0,7,9,11`.

## Design

Both formats share a storage-neutral array API, but retain their distinct metadata, chunk-key, dtype, and codec rules. Unknown or unsupported encodings must fail explicitly instead of returning incorrect values. See [the roadmap](docs/ROADMAP.md) for the staged interoperability targets.

## Specification and attribution

This project implements the publicly documented [Zarr v2 storage specification](https://zarr-specs.readthedocs.io/en/latest/v2/v2.0.html) and [Zarr v3 core specification](https://zarr-specs.readthedocs.io/en/latest/v3/core/). The [Zarr specifications repository](https://github.com/zarr-developers/zarr-specs) is CC BY 4.0. No upstream implementation code or test data has been copied into this repository. If interoperability fixtures derived from zarr-python are added, their provenance and MIT license will be recorded beside them.

This project is licensed under Apache-2.0; see [LICENSE](LICENSE).
