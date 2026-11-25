///|
fn benchmark_theory() -> Unit raise {
  let width = 64
  let columns = Array::makei(width, i => "c\{i}")
  let premises : Array[@inference.Rule] = []
  for from in 0..<width {
    for to in (from + 1)..<Int32::min(from + 9, width) {
      premises.push({ lhs: [columns[from]], rhs: columns[to], })
    }
  }
  let original = @inference.theory(columns, premises)
  let cover = original.minimal_cover()
  assert_eq(cover.status, @budget.CompleteInDomain)
  assert_eq(cover.rules.length(), width - 1)
  let reduced = @inference.theory(columns, cover.rules)
  let limits = { ..@budget.defaults(), max_work: 100000000L, }
  let checked = original.audit_cover(reduced, limits~)
  assert_true(checked.comparison.left_to_right is @inference.EntailsAll)
  assert_true(checked.comparison.right_to_left is @inference.EntailsAll)
  assert_true(checked.minimality is @inference.Irreducible)
  let keys = reduced.schema_keys()
  assert_eq(keys.keys.length(), 1)
  assert_true(reduced.verify_schema_key(keys.keys[0]))
  let reductions = []
  let audits = []
  for _ in 0..<7 {
    let start = @env.now()
    let current = original.minimal_cover()
    let after_cover = @env.now()
    let audit = original.audit_cover(reduced, limits~)
    let after_audit = @env.now()
    assert_eq(current.usage, cover.usage)
    assert_eq(audit.usage, checked.usage)
    reductions.push(after_cover - start)
    audits.push(after_audit - after_cover)
  }
  reductions.sort()
  audits.sort()
  let report : Json = {
    "experiment": "declared-rule-cover",
    "columns": width,
    "premises": premises.length(),
    "cover_rules": cover.rules.length(),
    "edits": cover.edits.length(),
    "cover_work": cover.usage.work,
    "audit_work": checked.usage.work,
    "cover_ms_sorted": reductions.map(ms => ms.to_string()),
    "audit_ms_sorted": audits.map(ms => ms.to_string()),
  }
  println(@codec.canonical(report))
}
