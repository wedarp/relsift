# 多列包含关系发现

从两份导出中寻找潜在连接条件时，逐列匹配会遗漏列之间的联合信息。`tuple-ind` 搜索不同表之间的有向一对一列映射，对每条映射检查源表元组集合是否被目标表元组集合包含。

## 正例与反例

```sh
moon run cmd/relsift --target native -- tuple-ind examples/composite-exports.json --format text
moon run cmd/relsift --target native -- tuple-ind examples/tuple-exports.json
moon run cmd/relsift --target native -- diagnose examples/tuple-exports.json examples/diagnose-tuple-ind.json
```

第一条命令发现 `orders[region, sku] ⊆ stock[warehouse, product]`。源表四行中有三个不同元组，目标表四个元组都不同。对应的目标列顺序由映射决定。第二份库存数据中，区域与商品分别能匹配，但没有联合元组 `["south", "P1"]`，所以搜索完整结束并返回零条多列关系。第三条命令退出 1，报告该元组及两条源记录。

## 搜索域和结果

- 源表与目标表 ID 不同。每侧列各不重复，元组按映射位置比较。源列按列 ID 固定顺序，目标列顺序与源侧一一对应，因此同一对表可有多种列映射。同一个映射的共同重排只报告一次。
- 默认宽度为二，可用 `--max-ind-width N` 搜索二至 N 列。结果包括这一范围内全部成立的映射。投影关系和扩展关系可以同时出现。
- `--target-unique-only true` 只输出目标元组在目标行重数下唯一的映射。目标侧有重复的短映射仍可用于扩展，较宽映射可能具有唯一目标。
- 空源的元组集合包含于任意目标集合；非空源无法包含于空目标。空目标的唯一性按零行成立。建议结合快照行数判断这种退化结果。所有表必须使用同一 NULL 策略。`equal` 将 NULL 作为独立值参与元组比较，与空串分开。

JSON 中 `source_distinct` 和 `target_distinct` 是不同元组数，`target_unique` 比较目标元组数和实际行数。结果按源表 ID、目标表 ID、宽度、位置对顺序排列。保留源行重数，集合成员检查共享重复元组。业务含义、目标唯一性是否长期稳定及外键约束均需另外确认。

## 库入口与独立复核

```moonbit
let options = { ..@inclusion.tuple_defaults(), max_width: 3 }
let result = @inclusion.discover_tuples([source, target], options~)
for relation in result.relations {
  if relation.source_table == source.id {
    let checked = @verify.tuple_inclusion(
      source, relation.source_columns, target, relation.target_columns,
    )
    assert_true(checked.holds is Some(true))
  }
}
```

导入 `wedarp/relsift/inclusion` 和 `wedarp/relsift/verify`，`source`、`target` 是两个已构建的 `model.Table`。生产搜索使用编码元组与投影剪枝，独立验证器按传入的有序列扫描原始值，并可报告失败候选的孤儿元组。复核涉及预算时，检查验证状态再使用计数。见 [诊断协议](diagnostics.md)。

## 索引、剪枝和预算

所有参与表共享精确值字典。缓存按表与有序列集合保存元组投影，目标映射顺序通过源元组重排换算到同一列顺序。整数数组键保留元组边界，哈希表按完整键值比较。先查单列包含，再按宽度扩展成立的映射。映射成立会推出删除任意一对位置后的包含关系，因此只对所有直接投影均成立的候选做元组成员检查。层级枚举与已知的多元 IND 搜索方法使用同一投影性质。 [VLDB 论文中的多元 IND 搜索](https://www.vldb.org/pvldb/vol8/p774-papenbrock.pdf)

`max_candidates` 按访问的单列对和已生成的多列候选计数，含投影剪枝。`max_work` 覆盖编码、投影构建、枚举、剪枝和逐元组检查等操作。`max_results` 按过滤后返回的已证关系计数。任何预算耗尽都返回 `partial` 与已经完整验证的映射。完整状态仅覆盖声明的表、宽度与唯一目标选项。`limits.max_lhs` 和 `limits.max_ucc_width` 不参与多列包含搜索。

`max_cached_projections` 默认为 128，限制一次搜索保留的投影条目总数。缓存满后，新的投影按需重建；设置为 0 可关闭缓存。报告记录实际构建数、当前缓存条目数和复用次数。候选数仍可能随列宽高速增长。引擎将编码数据和当前候选层保存在内存中，缓存条目数与操作数都无法限定硬内存用量。见 [基准实验](performance.md)。
