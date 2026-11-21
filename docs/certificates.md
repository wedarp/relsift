# 复核序列化报告

```sh
moon run cmd/relsift --target native -- discover examples/orders.csv --table-id orders > orders-report.json
moon run cmd/relsift --target native -- verify-report examples/orders.csv orders-report.json --table-id orders
```

`verify-report` 接受 `discover` 的版本 1 JSON 输出。它严格解析字段、计数、预算、完成标志及每条 `minimality: "proven"` 记录，然后通过直接行对比较验证 FD、唯一组合和所有删列证据。错误的行 ID、自配对、缺少证据、重复规则、未知列和超出声明宽度的规则都会使复核失败。结构非法退出 2；结构可读但证据无效退出 1；所列规则及证据全部有效退出 0。

输出包含 `valid`、`checked_fds`、`checked_uccs`、逐项 `issues` 和原始 `reported_status`。`completeness_verified` 始终是 false：复核已有规则不能证明报告没有漏掉其他规则，也不能证明历史运行实际消耗了声明的工作量。部分报告可以含有有效证据，复核成功不把它提升为完整报告。

输入表和报告必须按稳定表 ID 一一匹配；行数、列数、NULL 策略及退化标志也要吻合。元数据吻合不构成快照来源认证：本命令验证的是给定数据上的规则和证据，不提供签名或密码学历史证明。

库入口是 `@codec.parse_discovery_report(text)` 和 `@codec.recheck_report(tables, report)`。复核使用独立参考验证器，时间可能达到规则数量乘行数平方；它不执行生产搜索器，也不受发现预算隔离。CLI 对每个输入文件保留 8 MiB 大小限制。
