# 第三方来源

RelSift 的源码、文档与自编示例依照 [MIT 许可证](LICENSE) 提供。发现算法由本项目实现，使用等价分区、函数依赖与列集合搜索等公开概念。

| 来源 | 许可 | 使用范围 |
| --- | --- | --- |
| [MoonBit core](https://github.com/moonbitlang/core) | [Apache-2.0](https://github.com/moonbitlang/core/blob/main/LICENSE) | 编译时使用工具链随附的标准库，包括集合、JSON 和 CLI 的文件读写。源码包只包含本项目的源码与文档 |
| [GitHub Actions checkout](https://github.com/actions/checkout) 与 [setup-node](https://github.com/actions/setup-node) | [MIT](https://github.com/actions/checkout/blob/main/LICENSE) / [MIT](https://github.com/actions/setup-node/blob/main/LICENSE) | 由 CI 按固定提交调用 |
| [Node.js](https://github.com/nodejs/node) | [Node.js 许可证及随附声明](https://github.com/nodejs/node/blob/main/LICENSE) | 运行测试与基准脚本。脚本使用内置模块 |

`pkg.generated.mbti` 由 `moon info` 从本项目的公开接口生成。仓库内的订单、库存与其他小型测试样表由本项目构造。

## 公开基准数据

原始数据由运行者取得，源码包仅收录处理脚本、校验值和运行结果。具体转换与复现步骤见 [性能文档](docs/performance.md)。

- Horst、Hill、Gorman 编制的 Palmer Penguins，采集来源为 Kristen Gorman 与 Palmer Station LTER。使用 v0.1.0 的 `penguins.csv`，许可 CC0。 [数据来源](https://allisonhorst.github.io/palmerpenguins/)
- Cortez 等人的 Wine Quality，使用红、白葡萄酒两表，许可 CC BY 4.0。 [UCI 数据与引用](https://doi.org/10.24432/C56S3T)
- Nash 等人的 Abalone，使用 `abalone.data`，许可 CC BY 4.0。 [UCI 数据与引用](https://archive.ics.uci.edu/dataset/1/abalone)
- Fisher 的 Iris，使用 UCI 发布的 `iris.data`，许可 CC BY 4.0。 [UCI 数据与引用](https://doi.org/10.24432/C56C76)
