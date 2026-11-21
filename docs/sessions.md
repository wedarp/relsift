# 在候选之间让出执行

`session(table, limits?)` 创建内存搜索会话。`Session::step(quota)` 最多访问指定数量的候选，并保留同一个字典编码、分区缓存、遍历游标和已经证明的规则。

```moonbit
let search = @relsift.session(table)
while search.progress() is @relsift.Running {
  ignore(search.step(100))
  let interim = search.snapshot()
  // The host may inspect proved rules or yield its own event loop here.
  println(interim.usage.candidates)
}
let result = search.snapshot()
```

可运行示例：

```sh
moon run examples/stepped
moon run cmd/relsift --target native -- discover-stepped examples/orders.csv --table-id orders --step-candidates 1
```

库调用允许零配额：不初始化索引、不推进游标、不消耗预算。负配额为输入错误，不改变状态。CLI 必须使用正配额，默认 100；它循环调用到完成或预算耗尽，再输出一个普通发现报告。CLI 没有进程间恢复文件或交互控制协议。

| Progress | snapshot.status | 含义 |
| --- | --- | --- |
| `Running` | `partial`, reason=`yielded` | 暂时让出，可继续同一会话 |
| `Finished` | `complete_in_domain` | 声明宽度域完成 |
| `BudgetExhausted(reason)` | `partial`, reason 为耗尽项 | 累计预算耗尽，终态 |

反复 `step` 不会重置候选、工作或结果预算。终态再调用 `step` 不重新搜索。`snapshot()` 深复制可变结果数组，调用者修改副本不会影响缓存、剪枝或下一次快照。只有整条最小性证明完成后才发布规则。

分步与批量搜索共用候选判断、超集剪枝和证据生成代码，按相同顺序遍历同一声明域；完成后的 FD、UCC、证据和候选数一致。分步游标和批量递归遍历的工作计费不同，临近工作预算边界时截断位置可以不同。会话逐候选计入列位置长度加一的游标工作，其他分区和判断计费相同。

配额限制候选数，不限制每次调用的墙钟耗时：初始化索引或单个候选仍可扫描整表。工作计数不是内存或 CPU 隔离；当前只支持进程内继续，不序列化缓存、不跨快照迁移会话。宿主负责调度与生命周期。

测试对 341 张至多四行、两列的二值表分别使用 1、3、100 配额，核对批量结果、全部证据、分区数量和独立穷举；另用种子 20261121 检查 120 张至多六行、四列的多值表及变化配额。还检查零列、NULL/空串/Unicode 字面差异、域限制、快照修改隔离及累计预算终态。
