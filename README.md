# Zarr

A MoonBit implementation of the Zarr v2 and v3 storage formats for chunked N-dimensional arrays. This is an independent implementation, not an official Zarr Developers project.

## Status

Early development. The current code structurally parses regular-grid array metadata for both formats, constructs metadata/chunk keys, and provides an in-memory byte store. Dtype, fill-value and codec compatibility are not yet fully validated. The store accepts **already encoded** chunks; it does not yet decode codecs, expose numeric slicing, or access local/cloud files. Do not use it as a general Zarr reader/writer yet.

| Capability | Zarr v2 | Zarr v3 |
| --- | --- | --- |
| Parse regular-grid array metadata | Yes, common string dtypes | Yes, common string data types |
| Metadata and chunk keys | `.` and `/` separators | default and v2-compatible encodings |
| Raw encoded chunk storage | In-memory only | In-memory only |
| Decode/encode codecs and values | Planned | Planned |
| Groups, attributes, slices, filesystem/cloud stores | Planned | Planned |

## Build and run

Requires the MoonBit toolchain. From this directory:

```sh
moon check --deny-warn
moon build
moon test --deny-warn
moon run cmd/main
```

The example creates v3 metadata and a raw chunk in an in-memory store. It prints `Zarr v3 chunk samples/c/0: 2 bytes`.

## Design

Both formats share a storage-neutral array API, but retain their distinct metadata, chunk-key, dtype, and codec rules. Unknown or unsupported encodings must fail explicitly instead of returning incorrect values. See [the roadmap](docs/ROADMAP.md) for the staged interoperability targets.

## Specification and attribution

This project implements the publicly documented [Zarr v2 storage specification](https://zarr-specs.readthedocs.io/en/latest/v2/v2.0.html) and [Zarr v3 core specification](https://zarr-specs.readthedocs.io/en/latest/v3/core/). The [Zarr specifications repository](https://github.com/zarr-developers/zarr-specs) is CC BY 4.0. No upstream implementation code or test data has been copied into this repository. If interoperability fixtures derived from zarr-python are added, their provenance and MIT license will be recorded beside them.

This project is licensed under Apache-2.0; see [LICENSE](LICENSE).
