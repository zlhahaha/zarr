"""One-command real CT conversion, independent verification and MoonBit PNG preview."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import zlib

import numpy as np
import zarr

from verify_real_volume_pipeline import build_app, command, write_json
from verify_volume_pipeline import PROJECT


def decode_rgba_png(path):
    """Small independent oracle for the generated noninterlaced RGBA8 PNG."""
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    offset, compressed = 8, bytearray()
    width = height = None
    ended = False
    while offset < len(data):
        length = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4:offset + 8]
        payload = data[offset + 8:offset + 8 + length]
        crc = struct.unpack_from(">I", data, offset + 8 + length)[0]
        assert zlib.crc32(kind + payload) & 0xffffffff == crc
        if kind == b"IHDR":
            width, height, bits, color, compression, filtering, interlace = struct.unpack(">IIBBBBB", payload)
            assert (bits, color, compression, filtering, interlace) == (8, 6, 0, 0, 0)
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            ended = True
            break
        offset += length + 12
    assert ended and width and height
    raw = zlib.decompress(compressed)
    stride = width * 4
    assert len(raw) == height * (stride + 1)
    output = bytearray(height * stride)
    for y in range(height):
        mode = raw[y * (stride + 1)]
        assert 0 <= mode <= 4
        for x in range(stride):
            a = output[y * stride + x - 4] if x >= 4 else 0
            b = output[(y - 1) * stride + x] if y else 0
            c = output[(y - 1) * stride + x - 4] if y and x >= 4 else 0
            if mode == 0:
                prediction = 0
            elif mode == 1:
                prediction = a
            elif mode == 2:
                prediction = b
            elif mode == 3:
                prediction = (a + b) // 2
            else:
                p = a + b - c
                distances = [abs(p - a), abs(p - b), abs(p - c)]
                prediction = (a, b, c)[distances.index(min(distances))]
            output[y * stride + x] = (raw[y * (stride + 1) + 1 + x] + prediction) & 255
    return np.frombuffer(output, dtype=np.uint8).reshape(height, width, 4)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--download", action="store_true")
    parser.add_argument("--output-dir", type=Path, default=PROJECT / "_build/ct-showcase")
    args = parser.parse_args()
    root = args.output_dir.resolve()
    root.mkdir(parents=True, exist_ok=False)
    status = root / "showcase.json"
    write_json(status, dict(status="incomplete"))
    try:
        invocation = [sys.executable, str(PROJECT / "scripts/verify_real_volume_pipeline.py"),
                      "--source", "--trials", "1", "--output", str(root / "verification.json")]
        if args.download:
            invocation.append("--download")
        subprocess.run(invocation, cwd=PROJECT, check=True)
        report = json.loads((root / "verification.json").read_text(encoding="utf-8"))
        binary, _ = build_app(True)
        preview = PROJECT / "examples/zarr_preview"
        command(["moon", "check", "--target", "native", "--deny-warn"], preview)
        built = command(["moon", "run", "--target", "native", "--release", "--build-only", "."], preview)
        binaries = [p for line in built.splitlines() if line.startswith("{")
                    for p in json.loads(line).get("artifacts_path", [])]
        assert len(binaries) == 1
        images = []
        for case in report["cases"]:
            array_path = root / report["artifacts"] / case["samples"][0]["output"]
            volume = zarr.open_array(str(array_path), mode="r")[:]
            # Choose the first slice with the most nonzero voxels so the
            # cropped CT structure is visible. No contrast enhancement.
            plane = int(np.argmax(np.count_nonzero(volume, axis=(1, 2))))
            rgba, png = root / (case["name"] + ".rgba"), root / (case["name"] + ".png")
            exported = command([str(binary), "--export-slice", str(array_path), str(plane), str(rgba)], PROJECT)
            dimensions = json.loads(exported.strip().splitlines()[-1])
            command([binaries[0], str(rgba), str(dimensions["width"]), str(dimensions["height"]), str(png)], preview)
            actual = decode_rgba_png(png)
            values = volume[plane, :, :]
            expected = np.floor(values.astype(np.float64) * 255 + 0.5).astype(np.uint8)
            np.testing.assert_array_equal(actual[:, :, :3], np.repeat(expected[:, :, None], 3, axis=2))
            assert np.all(actual[:, :, 3] == 255)
            assert rgba.read_bytes() == actual.tobytes()
            repeated_export = subprocess.run([str(binary), "--export-slice", str(array_path), str(plane), str(rgba)],
                                             cwd=PROJECT, capture_output=True)
            assert repeated_export.returncode != 0 and rgba.read_bytes() == actual.tobytes()
            # Existing outputs are protected by exclusive file creation.
            repeated = subprocess.run([binaries[0], str(rgba), str(dimensions["width"]),
                                       str(dimensions["height"]), str(png)], cwd=preview, capture_output=True)
            assert repeated.returncode != 0
            images.append(dict(case=case["name"], plane=plane, png=png.name, width=dimensions["width"],
                               height=dimensions["height"], every_pixel_verified=True,
                               slice_selection="first plane with the largest nonzero voxel count; no contrast enhancement",
                               sha256=hashlib.sha256(png.read_bytes()).hexdigest()))
        write_json(status, dict(status="verified", verification="verification.json", images=images,
            scope="native MoonBit Zarr processing and RGBA export followed by separate native mizchi/image@0.5.0 PNG encoder; Python independently checks numerical arrays and PNG pixels; author-maintained integration, not external adoption; separate processes isolate async@0.20.3 and async@0.22.4"))
        print(f"verified showcase: {status}", flush=True)
    except BaseException as error:
        write_json(status, dict(status="failed", error=str(error)))
        raise


if __name__ == "__main__":
    main()
