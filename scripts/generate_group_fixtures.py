"""Generate nested v2/v3 groups and arrays with zarr-python 3.4.0."""

from pathlib import Path
import sys

PROJECT = Path(__file__).resolve().parents[1]
DEPS = PROJECT / ".interop-deps"
if DEPS.exists():
    sys.path.insert(0, str(DEPS))

import numpy as np
import zarr
from zarr.codecs import BytesCodec


def create(name: str, format_version: int):
    path = PROJECT / "integration" / "fixtures" / "zarr-python" / f"{name}.zarr"
    if path.exists():
        raise FileExistsError(path)
    root = zarr.open_group(store=str(path), mode="w", zarr_format=format_version)
    science = root.create_group("science")
    science.attrs["title"] = f"v{format_version}"
    options = (
        {"compressors": None, "filters": None}
        if format_version == 2
        else {"serializer": BytesCodec(), "compressors": [], "filters": []}
    )
    image = science.create_array(
        "image", shape=(3,), chunks=(2,), dtype=np.dtype("u1"),
        fill_value=5, **options,
    )
    image[2] = 9
    print(name)


def main() -> None:
    if zarr.__version__ != "3.4.0":
        raise RuntimeError(f"expected zarr-python 3.4.0, got {zarr.__version__}")
    create("v2_grouped_u8", 2)
    create("v3_grouped_u8", 3)


if __name__ == "__main__":
    main()
