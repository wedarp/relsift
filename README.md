| order_id | line_no | product_id | product_name |
|---|---|---|---|
| O1 | 1 | P1 | Pen |
| O1 | 2 | P2 | Book |
| O2 | 1 | P2 | Book |
| O2 | 2 | P1 | Pen |

# RelSift：数据关系实验手册

接手一份没有文档的数据导出时，可以先问三个问题：哪些列共同区分记录，哪些列值决定另一列，以及一张表的某列是否全部出现在另一张表中。RelSift 用 MoonBit 从原始行发现这些关系，并给出可重新检查的最小性证据。

**发现的是当前数据中观察到的规律，不是业务真理；约束需要人工确认。** 唯一组合不是已声明主键，包含关系不是已确认外键。

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

## 实验三：跨表关联候选

[examples/exports.json](examples/exports.json) 含订单和产品两个有显式 ID 的表。

```sh
moon run cmd/relsift --target native -- ind examples/exports.json --format text
moon run cmd/relsift --target native -- verify examples/exports.json examples/verify-ind.json
```

发现 `orders.product_id ⊆ products.product_id`，两侧不同值数量为 2、3，目标列唯一。反方向验证失败，孤儿摘要为 `P3`。目标有重复值时，包含仍可能成立，报告会将 `target_unique` 标为 `false`。

## 在 MoonBit 项目中使用

核心没有第三方模块依赖，不需要数据库、JVM、Python 或外部服务运行时。CLI 的文件读写使用随工具链分发的 `core/async`；Node.js 只用于集成测试。

源码可通过 `moon.work` 作为独立模块依赖，具体配置见 [API 文档](docs/api.md)。本仓库不以 `moon add` 命令暗示包已发布至 Mooncakes。

```moonbit
let t = @codec.parse_csv(csv_text, "orders")
let result = @relsift.discover(t)
for rule in result.fds {
  assert_true(@relsift.verify_fd(t, rule))
}
```

包导入配置与完整可运行代码见 [examples/library](examples/library/main.mbt)。

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

测试包括 689 张二值表的分区差分、同一范围的完整发现穷举、固定种子的 300 张多值表、最小性证据重检、失败用例缩减，以及行列变形与预算中断。测试数量不能替代对任意输入的数学证明。

原创源码采用 MIT，作者为 wedarp。使用的 MoonBit core 按上游 Apache-2.0 许可分发；不在仓库中复制其实现。分区与依赖发现属于已有研究领域，本项目不宣称发明这些数学概念。
