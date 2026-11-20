# MoonBit 核心 API

## 作为独立模块使用

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
  "wedarp/relsift@0.1.0",
}
```

本地成员按模块名称解析，版本来自工作区源码。锁定所使用的 RelSift Git 提交可固定源码版本。仓库当前提供源码工作区依赖方式，不要求 Mooncakes 登录或注册表发布。

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

完整签名由各包的 `pkg.generated.mbti` 给出，用 `moon info` 生成。常规调用应从根包和 `/inclusion` 进入；低层分区/发现入口供自定义实验使用。分区的列位置必须严格递增、无重复且在范围内；FD 右侧必须在范围内且不在左侧。

## 发现与复核

`Discovery.fds` 中的 `Fd` 含 `lhs`、`rhs`、`deletions`。`Discovery.uccs` 中的 `Ucc` 含 `columns`、`deletions`。每个 `Deletion` 给出 `removed` 列 ID 和两个不同的行 ID。返回值可独立序列化后重新检查；不要将报告中表 ID 相同误认为输入来源可信。

`verify_fd` 与 `verify_ucc` 同时检查约束成立和整组最小性证据。`verify.check_pair(table,parent,pair,rhs=Some(column))` 只检查某个具体 FD 反例；省略 `rhs` 时检查父集合上的碰撞。不合法的列 ID 是输入错误，伪造或缺失行对返回 false。

独立单约束验证返回 `Verdict { holds, counterexample }`。`verify.inclusion(source,source_column,target,target_column,orphan_limit=10)` 返回成立状态、不同值数量、目标唯一性、孤儿不同值总数和有界摘要；它适合复核失败候选，不会自动搜索其他列对。

## 异常与部分结果

`model.InputError::Invalid` 表示非法模式、NULL 策略或参数。根发现入口将 `budget.Exhausted` 转成 `Partial(reason)` 并返回已证明结果；其他执行错误向调用者传播。`CompleteInDomain` 需要结合 `limits` 解释。低层 `/dependency`、`/unique` 的输出数组必须初始为空；预算异常向外传播时，数组中只保留已经证明的结果。

算法与预算不依赖 IO。宿主负责文件读取、生命周期、进程限制及日志处理。核心可编译至 wasm、wasm-gc、JavaScript 和 native；原生/wasm CLI 使用工具链的实验性 `core/async`，因此工具链版本与 CI 归档固定。
