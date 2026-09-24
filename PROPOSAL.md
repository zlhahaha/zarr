# Zarr 项目申报书（供参赛者审阅、改写的草稿）

- **项目名称**：Zarr
- **项目方向**：MoonBit 科学数据与 AI 数据基础设施
- **GitHub 仓库**：https://github.com/zlhahaha/zarr
- **项目性质**：参考公开 Zarr v2/v3 存储规范的原创 MoonBit 实现；不移植 zarr-python 源码

## 为什么值得做

AI 应用不仅需要模型推理，也需要准备、浏览、筛选和交换大量结构化数值数据：图像与遥感影像、时空观测、实验结果、特征张量和嵌入向量都可能远大于一次请求所需的范围。Zarr 用分块、压缩的 N 维数组保存这些数据，使程序能按块或区域读取，而不必将整个数据集转成 JSON/CSV 或一次装入内存。MoonBit 若缺少兼容的 Zarr 读写层，开发者就难以直接复用 Python 科学计算与 AI 数据流程已有的数据资产，也难以把 MoonBit 生成的数据交还给这些流程。普通文件 API 不理解 Zarr 元数据、块网格和编解码；ndarray 解决数组计算，也不能替代存储格式互操作。因此需要一个可被多种上层应用复用的**数据交换与按需访问基础库**，而不是让每个项目各自实现格式解析器。

## 谁会用、怎么用

1. **AI 数据集与评测工具**：按切片读取数值特征、嵌入向量或实验指标；在 MoonBit 中筛选、汇总后，写回可由 Python 读取的数组。
2. **图像与遥感处理**：只取视窗涉及的影像块或栅格区域，供服务端预处理，避免传输整份数据。
3. **科研与工业观测**：按时间和空间范围读取显微图像、传感器或模拟数据，用于局部分析与结果展示。
4. **浏览器/Wasm 可视化**：对已加载到内存的数组做切片和解码，展示局部数据；浏览器远程获取不在当前版本承诺内。
5. **跨语言数据管线**：读取 zarr-python 产出的 v2/v3 数据，在 MoonBit CLI/服务中处理，再生成 Python 可打开的数据集。

## 核心功能与实际进度

- **已实现的早期版本**：v2/v3 数组、组与属性；常用布尔/整数/浮点类型、大小端、填充值、边界块和 N 维矩形切片；内存与原生文件存储；gzip/zstd（v2 另有 zlib）读写、部分 Blosc 只读；原生端 HTTP 按需读取。Python 双向兼容样本、可运行示例及 Linux/macOS/Windows、Wasm CI 已覆盖主要路径。
- **明确边界**：目前不支持全部 dtype/codec；Blosc 的 bitshuffle、BloscLZ 和写入尚未实现；HTTP 适配器仅原生端只读，尚无通用对象存储后端，也不提供模型训练、通用张量计算或完整 zarr-python API。
- **后续计划**：补齐常见 Blosc 组合、v3 sharding、远程存储与性能/内存基准；持续以独立 Python 样本验证互操作，并按测试结果扩充支持矩阵。

## 交付与开源说明

交付可复用 MoonBit 包、README/API 与使用边界、v2/v3 可运行示例、跨平台 CI、双向互操作测试和版本化更新记录；Mooncakes 发布是后续验收目标，须另行确认，当前仓库为未发布的源码预览版。项目采用 Apache-2.0；实现参考 [Zarr v2 规范](https://zarr-specs.readthedocs.io/en/latest/v2/v2.0.html)、[Zarr v3 规范](https://zarr-specs.readthedocs.io/en/latest/v3/core/)及公开的 [C-Blosc 块格式](https://github.com/Blosc/c-blosc/blob/main/README_CHUNK_FORMAT.rst)，第三方依赖与测试数据来源见仓库 README。
