// Learn more about moon.mod configuration:
// https://docs.moonbitlang.com/en/latest/toolchain/moon/module.html
//
// To add a dependency, run this command in your terminal:
//   moon add moonbitlang/x
//
// Or manually declare it in `import`, for example:
// import {
//   "moonbitlang/x@0.4.6",
// }

name = "zlhahaha/zarr"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/zlhahaha/zarr"

license = "Apache-2.0"

keywords = [ "zarr", "array", "scientific-data", "storage" ]

preferred_target = "native"

description = "Zarr v2 and v3 chunked array storage for MoonBit"

import {
  "moonbitlang/async@0.20.3",
}
