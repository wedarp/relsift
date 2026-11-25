| order_id | line_no | product_id | product_name |
|---|---|---|---|
| O1 | 1 | P1 | Pen |
| O1 | 2 | P2 | Book |
| O2 | 1 | P2 | Book |
| O2 | 2 | P1 | Pen |

# RelSift：数据关系实验手册

接手一份没有文档的数据导出时，可以先问三个问题：哪些列共同区分记录，哪些列值决定另一列，以及一张表的某列是否全部出现在另一张表中。RelSift 用 MoonBit 从原始行发现这些关系，并给出可重新检查的最小性证据。

**发现的是当前数据中观察到的规律，不是业务真理；约束需要人工确认。** 唯一组合不是已声明主键，包含关系不是已确认外键。

## 安装与运行

按 [MoonBit 安装指南](https://docs.moonbitlang.com/zh-cn/latest/tutorial/tour.html) 准备工具链，用 `moon version --all` 查看版本。本仓库用 `moon 0.1.20261104`、`moonc v0.10.20+65efd5b93` 和同版本 core 验证。原生目标需要平台 C 工具链，CLI 也可在 Moonrun 中使用 `--target wasm`。Node.js 24.19.0 用于 CLI 测试和公开数据基准。

```sh
git clone https://github.com/wedarp/relsift.git
cd relsift
moon run cmd/relsift --target native -- discover examples/orders.csv --table-id orders --format text
```

在已有 MoonBit 项目中执行 `moon add wedarp/relsift@0.4.0` 即可使用库。导入和最小调用见 [API 文档](docs/api.md)，发布版见 [Mooncakes](https://mooncakes.io/docs/wedarp/relsift@0.4.0)。

| 使用场景 | 可运行入口 | 可核查的输出 |
| --- | --- | --- |
| 理解无文档明细 | `discover` 读取四行订单 CSV | 8 条 FD、5 个最小唯一组合和删列反例 |
| 检查跨表关联 | `ind` 与 `diagnose` 读取 JSON 表 | 单列包含候选、目标唯一性与多列孤儿元组 |
| 检查下一份导出 | `compare` 读取新快照与发现报告 | 仍成立、失去最小性、违反规则、缺少列 |
| 精简和审查函数依赖 | `moon run examples/inference` | 等价最小覆盖、两行反模型和最小决定列组 |

相关命令详见下列实验和 [CLI 协议](docs/protocol.md)。版本变化见 [更新记录](CHANGELOG.md)。

## 实验一：完整发现，而不是只验证预设答案

上述数据在 [examples/orders.csv](examples/orders.csv)。令 `O=order_id`、`L=line_no`、`P=product_id`、`N=product_name`，全部左侧最小、单属性右侧的非平凡 FD 是：

| 右侧 | 全部最小左侧 |
|---|---|
| O | {L,P}、{L,N} |
| L | {O,P}、{O,N} |
| P | {N}、{O,L} |
| N | {P}、{O,L} |

全部最小唯一列组合是 `{O,L}`、`{O,P}`、`{O,N}`、`{L,P}`、`{L,N}`。没有常量列，因而没有空左侧 FD。`{O,P} → L` 等关系可能只是这四行的偶然规律，发现器如实保留。

在本目录运行：

```sh
moon run cmd/relsift --target native -- discover examples/orders.csv --table-id orders --format text
moon run examples/library
```

输出 8 条 FD、5 个最小唯一组合。省略 `--format text` 得到 JSON；每条最小结果都包含删除每个左侧列后的失败行对。`examples/library` 还调用独立验证器重新检查全部证据。

## 实验二：让一条假设失败

尝试声明 `order_id → product_id`：

```sh
moon run cmd/relsift --target native -- verify examples/orders.csv examples/verify-fd.json --table-id orders
```

退出码为 **1**，返回 `r1`、`r2`：两行 `order_id` 都是 `O1`，但产品分别为 `P1`、`P2`。

对 `{L,P} → O` 的最小性，删去 `L` 后可用第 1、4 行反驳，删去 `P` 后可用第 1、3 行反驳。实现可能选到其他同样有效的行对；证据必须在输入中成立，不要求固定为这两个例子。

将第一行完整复制一次：

```sh
moon run cmd/relsift --target native -- discover examples/orders-duplicate.csv --table-id orders --format text
```

FD 仍为 8 条，所有唯一组合失效。引擎保留实际行重数，不先去重。

需要查看全部冲突组、碰撞记录或孤儿来源时，可使用 `diagnose INPUT RULE.json`。它报告精确行对数量和来源行 ID，并明确区分完整计数、部分计数和未判定状态，见[精确诊断](docs/diagnostics.md)。

保存的发现 JSON 可用 `verify-report INPUT REPORT.json` 独立复核规则与每条删列证据；这不证明报告没有遗漏关系。见[报告证据复核](docs/certificates.md)。

接到下一份导出时，`compare INPUT BASELINE.json` 会重新检查旧规则，返回新的反例或更小成立集合，保留原报告的完成状态。见[快照回归](docs/regression.md)。

```sh
moon run cmd/relsift --target wasm -- discover examples/orders.csv --table-id orders > orders-report.json
moon run cmd/relsift --target native -- verify-report examples/orders.csv orders-report.json --table-id orders
moon run cmd/relsift --target native -- compare examples/orders-duplicate.csv orders-report.json --table-id orders
```

证据复核退出 0，比较退出 1，并报告五个唯一组合冲突。Windows PowerShell 5.1 使用 `Out-File -Encoding utf8` 保存报告，CLI 输入应为 UTF-8。

需要在候选之间让出控制时，可用库的 `session`/`step` API。分区缓存、遍历位置和预算保留在同一会话中；[分步示例](docs/sessions.md)同时展示报告证据复核。

## 实验三：跨表关联候选

[examples/exports.json](examples/exports.json) 含订单和产品两个有显式 ID 的表。

```sh
moon run cmd/relsift --target native -- ind examples/exports.json --format text
moon run cmd/relsift --target native -- verify examples/exports.json examples/verify-ind.json
```

发现 `orders.product_id ⊆ products.product_id`，两侧不同值数量为 2、3，目标列唯一。反方向验证失败，孤儿摘要为 `P3`。目标有重复值时，包含仍可能成立，报告会将 `target_unique` 标为 `false`。

已有明确的多列映射时，可以用 [多列包含诊断](docs/diagnostics.md#按位置验证多列包含关系) 复核整个元组。例如订单的「区域、商品」各自在库存表中出现，组合「south、P1」仍可能缺失。

## 在 MoonBit 项目中使用

计算核心仅依赖 MoonBit core。CLI 文件读写使用工具链随附的 `core/async`。Node.js 用于 CLI 集成测试和公开数据基准。

也可通过 `moon.work` 在同一工作区引用源码。导入示例见 [API 文档](docs/api.md)。

```moonbit
let t = @codec.parse_csv(csv_text, "orders")
let result = @relsift.discover(t)
for rule in result.fds {
  assert_true(@relsift.verify_fd(t, rule))
}
```

包导入配置与完整可运行代码见 [examples/library](examples/library/main.mbt)。

使用 `wedarp/relsift/inference` 可以对选定的函数依赖计算闭包、精简规则并比较两个规则集。订单示例把 8 条发现规则精简为 5 条等价规则，并独立复核；它也对比规则推导的最小决定列组和实际行的唯一性。见 [推导示例和 API](docs/inference.md)。

## 算法与边界

`partition` 用字符串字典编码、复合分区求交及缓存支持 `dependency` 和 `unique`。搜索按集合宽度递增；成立的 FD/UCC 对超集进行剪枝，每条返回结果都有完整删除证据。`inclusion` 构造跨表单列值集合并检验有向包含。`verify` 使用独立的直接行对或数组集合实现，不调用生产分区算法。

空串与 NULL 分开；不转换数值、大小写或 Unicode。默认拒绝 NULL，JSON 可显式选择把 NULL 当作独立值。具体输入契约见 [数据语义](docs/semantics.md)。

默认 FD 左侧和 UCC 最大宽度均为 4。状态 `complete_in_domain` 只保证声明域内完成；`partial` 表示预算耗尽，空结果不能解释为没有关系。操作计数不是硬内存或 CPU 隔离。见 [算法与预算](docs/algorithms.md)、[JSON 协议与退出码](docs/protocol.md)及[实测性能](docs/performance.md)。

第一版仅发现精确 FD、最小 UCC、跨表单列 IND，不发现近似依赖、因果关系或完整复合外键，不执行自动范式分解。列子集搜索具有指数规模，不能承诺任意宽表高效。

## 复现实验

固定工具链：`moonc v0.10.20+65efd5b93`、`moon 0.1.20261104`，随附 core 同版本。原生构建需要平台 C 工具链。Windows 已运行 native，CI 使用固定归档及 SHA-256 校验在 Linux 运行。

```sh
moon fmt --check
moon check --target all --deny-warn
moon test --target wasm-gc --deny-warn
moon test --target js --deny-warn
moon test --target native --deny-warn
moon build --target native --release --deny-warn
node --test tests/cli.test.mjs
moon run examples/performance --target native --release
```

测试包括 689 张二值表的分区差分、同一范围的完整发现穷举、固定种子的 300 张多值表、最小性证据重检、失败用例缩减，以及行列变形与预算中断。新增的推导差分逐一检查 100 组规则的 32 种种子集合和所有目标列。

源码与项目示例使用 [MIT 许可证](LICENSE)，版权人为 wedarp。运行时、CI 工具和基准数据的来源与许可见 [第三方来源](THIRD_PARTY.md)。
