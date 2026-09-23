# Zarr 项目申报书（草稿）

- 项目名称：Zarr
- 项目方向：MoonBit 科学数据与分块数组基础库
- GitHub 仓库：https://github.com/zlhahaha/zarr
- 项目性质：原创 MoonBit 实现，参考公开 Zarr v2/v3 存储规范；不是移植 zarr-python 代码

## 项目简介与价值

MoonBit 缺少可与 Python 科学计算生态交换 Zarr 数据的通用读写库。Zarr 以可分块、可压缩的 N 维数组承载大规模科学数据。本项目让 MoonBit 程序能直接读取和生成符合 v2/v3 规范的数据，而不必先整体转换成 JSON/CSV。目标用户包括数据工具、浏览器/Wasm 可视化、图像与地理数据处理开发者。

## 预期使用场景

1. 读取 Python/Zarr 生成的多维数组，仅访问所需块或切片。
2. 在 MoonBit 工具中创建或修改 Zarr 数据，再交给 Python 生态使用。
3. 在浏览器或服务端按块预览大型图像、时空或模拟数据。

## 核心功能与边界

- v2/v3 元数据、数组与组、属性、规则块网格、自动识别格式和安全路径处理。
- 常用数值类型与大小端、填充值、边界块、N 维切片和读写；先覆盖无压缩及主流 gzip/zstd，随后扩展 Blosc 与 v3 sharding。
- 可替换 Store 抽象，先提供内存和本地文件，后续增加 HTTP 只读及对象存储适配。
- 不重复实现通用 ndarray 数值计算；首版不承诺所有扩展类型和第三方 codec。

## 实现路线与验收产物

先完成规范元数据与块寻址，再做数值数组读写、编解码和切片，最后补充层级、远程存储、性能与边界测试。交付可安装 Mooncakes 包、README/API 文档、可运行示例、GitHub CI，以及由 zarr-python 双向生成/读取的 v2/v3 兼容性测试。

参考：[Zarr v2 规范](https://zarr-specs.readthedocs.io/en/latest/v2/v2.0.html)、[Zarr v3 规范](https://zarr-specs.readthedocs.io/en/latest/v3/core/)；规范仓库为 CC BY 4.0，本项目代码采用 Apache-2.0，不复制上游实现代码。
