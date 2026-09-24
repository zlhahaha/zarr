"""Generate a v3 inline-consolidated hierarchy with zarr-python 3.4.0."""

from pathlib import Path
import sys

PROJECT = Path(__file__).resolve().parents[1]
DEPS = PROJECT / ".interop-deps"
if DEPS.exists():
    sys.path.insert(0, str(DEPS))

import numpy as np
import zarr
from zarr.codecs import BytesCodec


def main() -> None:
    if zarr.__version__ != "3.4.0":
        raise RuntimeError(f"expected zarr-python 3.4.0, got {zarr.__version__}")
    path = (
        PROJECT / "integration" / "fixtures" / "zarr-python"
        / "v3_consolidated_grouped_u8.zarr"
    )
    if path.exists():
        raise FileExistsError(path)
    root = zarr.open_group(store=str(path), mode="w", zarr_format=3)
    science = root.create_group("science")
    science.attrs["title"] = "consolidated-v3"
    image = science.create_array(
        "image", shape=(3,), chunks=(2,), dtype=np.dtype("u1"),
        fill_value=5, serializer=BytesCodec(), compressors=[], filters=[],
    )
    image[2] = 9
    zarr.consolidate_metadata(str(path), zarr_format=3)
    print("v3_consolidated_grouped_u8")


if __name__ == "__main__":
    main()
