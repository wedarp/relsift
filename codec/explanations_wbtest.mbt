///|
test "diagnosis summaries keep unknown holds and partial counts distinct" {
  let t = certificate_fixture()
  let request = "{\"kind\":\"fd\",\"table\":\"t\",\"lhs\":[\"a\"],\"rhs\":\"b\"}"
  let full = explain_diagnosis(diagnose([t], request))
  assert_true(full.contains("已找到反例"))
  assert_true(full.contains("冲突组 2，违反行对 2"))
  assert_true(full.contains("计数完整"))
  let unknown = explain_diagnosis(
    diagnose([t], request, limits={ ..@budget.defaults(), max_work: 0L, }),
  )
  assert_true(unknown.contains("尚未判定"))
  assert_true(unknown.contains("计数仅为下界"))
  let partial = explain_diagnosis(
    diagnose([t], request, limits={ ..@budget.defaults(), max_results: 0, }),
  )
  assert_true(partial.contains("已找到反例"))
  assert_true(partial.contains("计数仅为下界"))
}

///|
test "unique and inclusion summaries report multiplicity and target uniqueness" {
  let t = certificate_fixture()
  let unique = unique_diagnosis(@verify.diagnose_unique(t, ["a"]))
  let text = explain_diagnosis(unique)
  assert_true(text.contains("碰撞组 2，碰撞行对 2，超额记录 2"))
  let ind = inclusion_diagnosis(@verify.diagnose_inclusion(t, "a", t, "b"))
  assert_true(
    explain_diagnosis(ind).contains(
      "孤儿值 2，孤儿记录 4；目标唯一：否",
    ),
  )
}

///|
test "recheck and replay explanations never upgrade a partial baseline" {
  let t = certificate_fixture()
  let partial = @engine.discover(t, limits={
    ..@budget.defaults(),
    max_work: 0L,
  })
  let baseline = parse_discovery_report(canonical(envelope(partial)))
  let text = explain_recheck(recheck_report([t], baseline))
  assert_true(text.contains("所列规则与证据有效"))
  assert_true(text.contains("原报告状态：部分结果"))
  assert_true(text.contains("未验证搜索完整性"))
  let replay = explain_regression(compare_report([t], baseline))
  assert_true(replay.contains("声明域内完成"))
  assert_true(replay.contains("基线状态：部分结果"))
  assert_true(replay.contains("未搜索新增关系"))
}
