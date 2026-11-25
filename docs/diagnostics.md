# 指定约束的精确诊断

`verify` 入口给出一个直接反例，`diagnose` 则按约束聚合全部失败来源。两者都使用原始单元格的精确相等语义。

```sh
moon run cmd/relsift --target native -- diagnose examples/orders.csv examples/verify-fd.json --table-id orders
moon run cmd/relsift --target native -- diagnose examples/exports.json examples/verify-ind.json
```

FD 诊断返回相同左侧值的冲突组、组内所有行 ID、右侧不同值数量及右侧不相等的无序行对数量。该数量通过组频数精确计算，不构造全部行对。每组另有可被 `verify.check_pair` 直接重检的行对。

UCC 诊断返回每个碰撞值组合、组内行 ID、碰撞行对数，以及超过每组首行的记录数 `excess_rows`。完整重复记录保留。IND 诊断返回孤儿不同值及其全部源行 ID，NULL 与空串仍严格区分；目标是否唯一单独报告。

API 为 `verify.diagnose_fd`、`verify.diagnose_unique`、`verify.diagnose_inclusion`，均接受发现预算。`max_results` 限制输出组数，不能当作总行 ID 数或硬内存上限。IND 请求中可选的非负 `orphan_limit` 与 `max_results` 取较小值，作为更紧的组数预算；截断仍会返回部分状态。

`holds` 为 true、false 或 null：完整扫描无反例才返回 true；已找到反例可返回 false，即使后续被截断；尚未判定时返回 null。`counts_complete=false` 表示计数只是已完成工作给出的下界，不能解释为完整总数。只有 `complete_in_domain` 才保证所有失败组和计数完整。行对计数以十进制字符串输出。

CLI 退出码沿用 0（成立）、1（不成立）、2（非法或失败）、3（诊断预算耗尽）。诊断结果的 `groups` 可能包含敏感原值和行 ID，保存与分享由调用者控制。

## 按位置验证多列包含关系

```sh
moon run cmd/relsift --target native -- diagnose examples/tuple-exports.json examples/diagnose-tuple-ind.json --format text
```

使用 `kind: "tuple_ind"` 与 `source_columns`、`target_columns` 数组。两侧按相同下标配对，例如 `["region", "sku"]` 对应 `["warehouse", "product"]`。两侧宽度必须相同且非零，各侧列 ID 不得重复，NULL 策略必须一致。整个元组按原始值比较，字符串中的分隔符保持原样。

示例中的两个单列投影都满足包含，但元组 `["south", "P1"]` 缺失。命令退出 1，返回第一个源行 ID `o2` 与源记录数 2。目标元组重复只影响 `target_unique`。库入口为 `@verify.tuple_inclusion`，自动发现入口 `ind` 仍搜索单列。

`orphan_limit` 只控制取样数量，允许设为 0 只取计数。完整扫描时 `orphan_tuples` 和 `orphan_rows` 分别是不同孤儿元组数及对应源行数。`max_results` 作为独立的运行预算，耗尽时返回 `partial`。`source_rows_checked` 记录已计入统计的前缀，部分计数是下界。扫描可以先证实存在反例，继而因为预算耗尽而没有把该行计入统计。目标扫描完成前，目标基数和唯一性均为 `null`。
