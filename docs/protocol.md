# CLI 与结果协议，版本 1

```sh
moon run cmd/relsift --target native -- discover INPUT.csv --table-id export
moon run cmd/relsift --target native -- discover INPUT.json
moon run cmd/relsift --target native -- ind INPUT.json
moon run cmd/relsift --target native -- verify INPUT.json RULE.json
moon run cmd/relsift --target native -- diagnose INPUT.json RULE.json
moon run cmd/relsift --target native -- verify-report INPUT.json REPORT.json
moon run cmd/relsift --target native -- compare INPUT.json BASELINE.json
moon run cmd/relsift --target native -- discover-stepped INPUT.json --step-candidates 100
```

`--target wasm` 也可在 Moonrun 宿主中运行 CLI。JavaScript 和 wasm-gc 用于核心库与无 IO 示例，CLI 未声明支持这两个后端。原生二进制编译后可直接执行，无需 MoonBit 编译器或 Node.js。

输入由小写扩展名 `.csv`、`.json` 选择。CLI 不写回输入，不自动修复，也不自行创建输出文件；结果写到标准输出，调用者可自行重定向。`--table-id` 仅接受 CSV 输入；JSON 已有显式 ID，覆盖选项会被拒绝。默认格式为 JSON，可选 `--format text`。验证、诊断、报告复核和快照回归的文本格式会先给简短中文结论，再保留一行完整 JSON；发现和 IND 文本模式输出关系解释。

发现预算可用 `--max-lhs`、`--max-ucc-width`、`--max-candidates`、`--max-work`、`--max-results` 显式设置。每个选项必须提供一个值，未知或重复选项拒绝；不采用后值覆盖。命令与全部参数先验证，再读取文件。

| 命令 | 接受的预算选项 |
| --- | --- |
| `discover`、`discover-stepped` | 所有五个发现预算选项 |
| `ind`、`diagnose`、`compare` | 候选、工作、结果数量；不接受发现宽度选项 |
| `verify`、`verify-report` | 不接受预算选项；独立参考验证不受生产预算控制 |

需要预算内判定单个约束时使用 `diagnose`。`--step-candidates` 仅适用于 `discover-stepped`。这些限制避免参数被接受却未作用于实际执行。

JSON 中的 Int32 计数、宽度和 `orphan_limit` 必须是范围内的非负整数值，小数不会截断后继续执行；例如 1.0 表示整数 1，而 1.5 非法。Int64 字段必须是无前导零、无正号的非负十进制字符串。

## 状态和退出码

| 退出码 | `status.kind` | 含义 |
|---:|---|---|
| 0 | `complete_in_domain` | 发现搜索走完声明域 |
| 0 | `validated`，`holds=true` | 指定约束独立验证成立 |
| 1 | `validated`，`holds=false` | 指定约束不成立，附具体反例/孤儿摘要 |
| 2 | `failed` | 输入非法、IO 或其他执行失败；不提供发现完成结论 |
| 3 | `partial` | 预算耗尽，仅保留已经完整证明的结果 |

`diagnose` 的完整状态使用 `complete_in_domain`，成立退出 0，失败退出 1，计数未完成退出 3，详见[诊断字段](diagnostics.md)。`verify-report` 使用 `rechecked`，证据有效退出 0、无效退出 1；[证据复核](certificates.md)不证明完整性。`compare` 完成所列基线检查后退出 0；出现反例或缺列退出 1；部分检查退出 3，详见[回归协议](regression.md)。`discover-stepped` 返回普通发现记录，具体语义见[分步搜索](sessions.md)。

所有 CLI JSON 封装带 `schema_version:1`。多表发现的顶层状态汇总每表状态；顶层部分结果原因为 `table_budget`，具体耗尽项在相应表的 `status.reason` 中。不能只读 `fds`/`uccs` 是否为空而忽略状态和域。

## 发现记录

每表记录包含表 ID、行列数、NULL 策略、`limits`、`usage`、`fd_complete`、`ucc_complete`、`degenerate`、`fds`、`uccs`。

```json
{
  "lhs": ["product_id"],
  "rhs": "product_name",
  "minimality": "proven",
  "deletions": [{
    "removed": "product_id",
    "pair": {"first": "r1", "second": "r2"}
  }]
}
```

UCC 使用 `columns`，删除证据结构相同。空左侧和空唯一组合正常使用空证据数组。列集合按列 ID 字典序排列；FD 按左侧宽度、集合遍历顺序、右侧 ID 排列，UCC 按宽度和集合遍历顺序排列。行 ID 顺序固定证据选择。JSON 对象键递归字典序排列，数组保留上述语义顺序。表集合和 IND 的表/列对也按 ID 排列。

`work`、`max_work`、`partitions`、`cache_hits` 是 Int64，以十进制 JSON **字符串**输出，避免消费方丢失整数精度。其他计数为 Int32 数字。固定输入和参数产生确定性结果；不同版本的工作单位调整不保证计数不变。

IND 每条记录含 `source_table`、`source_column`、`target_table`、`target_column`、`source_distinct`、`target_distinct`、`target_unique`。不默认输出失败列对。

## 指定约束验证请求

```json
{"kind":"fd","table":"orders","lhs":["order_id"],"rhs":"product_id"}
```

```json
{"kind":"unique","table":"orders","columns":["order_id","line_no"]}
```

```json
{"kind":"ind","source_table":"products","source_column":"product_id","target_table":"orders","target_column":"product_id","orphan_limit":3}
```

FD 和 UCC 返回 `holds` 及 `counterexample`；成立时反例为 JSON null，失败时给不同行 ID。FD 的右侧必须不属于左侧；列 ID 重复、缺失列及未知表拒绝。IND 请求的 `orphan_limit` 可省略，默认 10，非负。返回精确的孤儿不同值数量、最多指定数量的字面值（或 JSON null）和省略数量，摘要截断不改变 `holds`。孤儿值按稳定行 ID 的首次出现顺序保存，不默认泄露所有失败列对。
