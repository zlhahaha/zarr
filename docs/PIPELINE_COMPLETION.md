# Volume application completion protocol

The author-maintained application now detects incomplete products without adding
transactions or resume to the Zarr library. This protocol belongs to the example,
not the Zarr specification. The example uses `zlhahaha/zarr@0.10.1`.

## Contract

1. Validate arguments, open the input and read the first tile before creating output.
2. Exclusively create the output directory. Any existing directory is rejected,
   including an incomplete previous run or a directory containing unrelated files.
   Its parent must already exist.
3. Write `pipeline-status.json` with `schema_version: 1, status: incomplete`
   through the library's single-key replacement path, before array metadata.
4. Write all shards and processing provenance.
5. Replace the marker with `status: complete`, shape, voxel count and shard count
   only after the preceding writes have succeeded.

The final marker uses the same data-synced temporary-file/rename mechanism as
other `FileStore::put` calls. This does not introduce a cross-key transaction,
directory-sync power-loss durability guarantee or concurrent-writer policy.

Before consuming the product, from `examples/volume_pipeline`:

```sh
moon run --target native . --check /absolute/path/to/output.zarr
```

Success prints `{"status":"complete","shards":...}` and exits zero. Missing,
malformed or incomplete markers, mismatched shape/shard count/layout, invalid float32
metadata and missing/nonregular shard paths are rejected. This checker targets
the application's fixed `[8,32,32]` outer shard layout.

Generic Python/Zarr readers do not automatically enforce this application marker.
The check confirms completion and expected file presence; it does not checksum
every stored value or protect against later edits. Use the independent numerical
verifier for content correctness. Do not consume arrays from failed or interrupted
runs, even if ordinary Zarr readers return plausible fill values.

For a failed run, retain it for diagnosis and choose a **new destination** to rerun.
There is no automatic resume or deletion of partial output. PNG and RGBA exports
also use exclusive creation and reject existing files.

## Reproduce the failure checks

From the repository root with the pinned Python dependencies installed:

```sh
python scripts/verify_pipeline_failures.py --output _build/pipeline-failures.json
```

The test runs actual native executables with deterministic generated data:

- A server returns 403 after at least one shard has committed.
- A directory at the next shard key forces a real filesystem replacement failure.
- The process is terminated while awaiting a subsequent payload, after an earlier shard exists.
- A successful product loses one shard while retaining its complete marker.
- A product has no marker or malformed marker JSON.

It checks nonzero status, incomplete/rejected output, and byte preservation when
attempting to reuse a failed destination. It also checks a normal successful
product. Temporary fixtures and processes are owned by the harness. Standard CI
runs this without depending on the public scientific dataset.
