# 把观察规则带到下一份导出

```sh
moon run cmd/relsift --target native -- discover examples/orders.csv --table-id orders > baseline.json
moon run cmd/relsift --target native -- compare examples/orders-duplicate.csv baseline.json --table-id orders
```

新快照多了一条重复记录。回归检查仍认可全部 8 条 FD，但对 5 个原有唯一组合返回新快照中的碰撞行对，退出 1。它不会把旧报告的最小性反例直接套用到新行上。

每条基线规则有四种结果：

| kind | 含义 |
| --- | --- |
| `held_minimal` | 当前仍成立，删除任意一列后均不成立 |
| `held_nonminimal` | 当前仍成立，但给出的 `smaller_columns` 也成立 |
| `violated` | 当前不成立，附当前行 ID 的 `counterexample` |
| `missing_columns` | 当前缺少列 ID，不能进行同一规则的值比较 |

删除任意一列的父集合均失败足以证明左侧最小；`smaller_columns` 是一个更小的成立集合，并不保证自身最小。空集合按定义处理。缺少整个表或改变 NULL 策略属于输入错误，退出 2。改名时保留稳定列 ID 可以继续匹配；仅保留显示名称而改变 ID 会被视为缺列。

`@regression.compare(table, baseline, limits?)` 使用直接行对扫描，独立于分区索引。它逐条重新检查 FD 与 UCC，计入候选、工作和输出预算；宽度限制是发现域的定义，不会过滤已经给出的基线规则。输出 `baseline_rules` 是 Int64 十进制字符串，`checked_rules` 只计算完全判定并输出的记录。预算耗尽退出 3；未完成规则不带已判定标签。每张表独立获得同样预算。

`baseline_status` 和原先两个完成标志独立保留。新检查完成只表示所列基线规则已检查完毕，不扩大旧搜索域，也不消除旧报告的截断。`new_rules_searched` 恒为 false；本操作不发现新规则或 IND 回归。新增表列在 `untracked_tables` 中。仍成立但不再最小的规则不会导致退出 1，缺列和反例会导致退出 1。

基线是声明集合，不是经过认证的历史。`baseline_authenticated` 恒为 false。需要确认其在旧快照上有效时，应先使用 `verify-report` 和原始输入复核；仍然需要人工确认业务意义。
