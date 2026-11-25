# MoonBit 核心 API

## 作为独立模块使用

在消费项目中安装发布版：

```sh
moon add wedarp/relsift@0.4.0
```

导入路径为 `wedarp/relsift`，数据模型位于 `wedarp/relsift/model`，验证器位于 `wedarp/relsift/verify`。

## 引用本地源码

将本仓库与消费项目放在同一工作区中，例如：

```text
workspace/
  moon.work
  relsift/
  analysis/
    moon.mod
    moon.pkg
    main.mbt
```

工作区 `moon.work`：

```moonbit
members = ["relsift", "analysis"]
```

消费项目 `moon.mod`：

```moonbit
name = "wedarp/analysis"
version = "0.1.0"
import {
  "wedarp/relsift@0.4.0",
}
```

本地成员按模块名称解析，版本来自工作区源码。锁定所使用的 RelSift Git 提交可固定源码版本。

消费项目 `moon.pkg`：

```moonbit
import {
  "wedarp/relsift" @relsift,
  "wedarp/relsift/model",
  "wedarp/relsift/budget",
}
pkgtype(kind: "executable")
```

```moonbit
fn main raise {
  let t = @model.table(
    "export",
    [{ id: "code", name: "Code" }],
    [
      { id: "r1", cells: [Some("01")] },
      { id: "r2", cells: [Some("1")] },
    ],
  )
  let limits = { ..@budget.defaults(), max_ucc_width: 1 }
  let result = @relsift.discover(t, limits~)
  assert_eq(result.status, @budget.CompleteInDomain)
  assert_eq(result.uccs[0].columns, ["code"])
  assert_true(@relsift.verify_ucc(t, result.uccs[0]))
}
```

## 包职责与入口

| 包 | 主要入口 |
|---|---|
| `wedarp/relsift` | `discover(Table, limits?)`；`verify_fd(Table,Fd)`；`verify_ucc(Table,Ucc)` |
| `/model` | `table(id,columns,rows,policy?)`；`Table::rows/columns/positions` |
| `/budget` | `defaults()`、`Limits`、`Status`、`Usage`；低层计数器与惰性组合遍历 |
| `/partition` | `index(Table,Meter)`；`Index::fd/unique/witness` |
| `/dependency` | `Fd`、`Deletion`；向初始空数组输出已证明的最小 FD |
| `/unique` | `Ucc`；向初始空数组输出已证明的最小 UCC |
| `/inclusion` | `discover(Array[Table],limits?) -> Report` |
| `/verify` | `fd`、`unique`、`inclusion`、`check_pair`，均为独立参考实现 |
| `/codec` | `parse_csv`、`parse_tables`、`validate`、结果 JSON 转换、`canonical`、`explain` |
| `/regression` | `compare(Table, Discovery, limits?)`，对新快照重新判定旧规则 |
| `/inference` | `theory(columns,rules)`，精确闭包、蕴含判定、最小覆盖、规则集比较与模式候选键 |

完整签名由各包的 `pkg.generated.mbti` 给出，用 `moon info` 生成。常规调用应从根包和 `/inclusion` 进入；低层分区/发现入口供自定义实验使用。分区的列位置必须严格递增、无重复且在范围内；FD 右侧必须在范围内且不在左侧。

## 发现与复核

`Discovery.fds` 中的 `Fd` 含 `lhs`、`rhs`、`deletions`。`Discovery.uccs` 中的 `Ucc` 含 `columns`、`deletions`。每个 `Deletion` 给出 `removed` 列 ID 和两个不同的行 ID。返回值可独立序列化后重新检查；不要将报告中表 ID 相同误认为输入来源可信。

`verify_fd` 与 `verify_ucc` 同时检查约束成立和整组最小性证据。`verify.check_pair(table,parent,pair,rhs=Some(column))` 只检查某个具体 FD 反例；省略 `rhs` 时检查父集合上的碰撞。不合法的列 ID 是输入错误，伪造或缺失行对返回 false。

独立单约束验证返回 `Verdict { holds, counterexample }`。`verify.inclusion(source,source_column,target,target_column,orphan_limit=10)` 返回成立状态、不同值数量、目标唯一性、孤儿不同值总数和有界摘要；它适合复核失败候选，不会自动搜索其他列对。

根包另提供 `session(Table,limits?)`、`Session::step(quota)`、`Session::snapshot()` 和 `Session::progress()`，见[分步搜索](sessions.md)。快照中的结果数组独立于会话内部状态。

`verify.diagnose_fd`、`diagnose_unique`、`diagnose_inclusion` 提供有预算的[冲突来源诊断](diagnostics.md)。`codec.parse_discovery_report` 与 `recheck_report` 支持[序列化证据复核](certificates.md)；`codec.compare_report` 提供多表[快照回归](regression.md)。低层 `dependency.consider` 和 `unique.consider` 用于单候选实验，输入位置必须有序无重复，已有输出数组必须只含在同一快照上证明的最小规则；不应把未验证的外部声明用作剪枝依据。

`codec.explain_diagnosis`、`explain_recheck`、`explain_regression` 接受该包生成的相应 JSON 报告，返回中文摘要。摘要保留部分状态、未知成立状态与原基线完成声明；详细证据仍在 JSON 报告中。CLI 用 `--format text` 调用这些入口。

`inference.Theory` 可以重复查询同一组前提，`closure` 返回所有已证属性、`implies` 回答单一目标、`explain` 提取已有证明中目标所需的步骤。使用 `minimal_cover` 精简规则，`audit_cover` 独立复核双向等价和最小性，`compare` 比较两组规则，`schema_keys` 推导模式候选键。见 [推导、预算与证据契约](inference.md)。

## 异常与部分结果

`model.InputError::Invalid` 表示非法模式、NULL 策略或参数。根发现入口将 `budget.Exhausted` 转成 `Partial(reason)` 并返回已证明结果；其他执行错误向调用者传播。`CompleteInDomain` 需要结合 `limits` 解释。低层 `/dependency`、`/unique` 的输出数组必须初始为空；预算异常向外传播时，数组中只保留已经证明的结果。

算法与预算不依赖 IO。宿主负责文件读取、生命周期、进程限制及日志处理。核心可编译至 wasm、wasm-gc、JavaScript 和 native；原生/wasm CLI 使用工具链的实验性 `core/async`，因此工具链版本与 CI 归档固定。
