///|
fn sample(
  rows : Array[Array[String?]],
  ids~ : Array[String] = ["a", "b"],
) -> @model.Table raise {
  @model.table(
    "t",
    ids.map(id => { id, name: id, }),
    rows.mapi((i, cells) => { id: "r\{i}", cells, }),
  )
}

///|
test "duplicate rows preserve FDs and violate every observed key with new witnesses" {
  let rows = [[Some("x"), Some("1")], [Some("y"), Some("2")]]
  let before = sample(rows)
  let baseline = @engine.discover(before)
  let next = sample([rows[0], rows[1], rows[0]])
  let report = compare(next, baseline)
  assert_true(report.status is @budget.CompleteInDomain)
  assert_eq(
    report.checked_rules,
    baseline.fds.length() + baseline.uccs.length(),
  )
  for check in report.checks {
    match (check.rule, check.outcome) {
      (Functional(_, _), HeldMinimal) => ()
      (Unique(columns), Violated(pair)) =>
        assert_true(@verify.check_pair(next, columns, pair))
      _ => fail("unexpected duplicate-row regression outcome")
    }
  }
}

///|
test "removed data can make a valid rule nonminimal without violating it" {
  let before = sample([[Some("x"), Some("1")], [Some("y"), Some("2")]])
  let next = sample([[Some("x"), Some("1")]])
  let report = compare(next, @engine.discover(before))
  for check in report.checks {
    assert_true(check.outcome is HeldNonminimal([]))
  }
}

///|
test "missing columns and incompatible NULL policies are explicit" {
  let before = sample([[Some("x"), Some("1")], [Some("y"), Some("2")]])
  let missing = sample([[Some("x")]], ids=["a"])
  let report = compare(missing, @engine.discover(before))
  assert_true(report.checks.any(c => c.outcome is MissingColumns(_)))
  let different = @model.table(
    "t",
    before.columns(),
    before.rows(),
    policy=@model.NullAsValue,
  )
  let rejected = try {
    ignore(compare(different, @engine.discover(before)))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
}

///|
test "budget truncation preserves baseline status and never reports an unfinished check" {
  let t = sample([[Some("x"), Some("1")], [Some("y"), Some("2")]])
  let baseline = @engine.discover(t)
  for work in 0..<80 {
    let r = compare(t, baseline, limits={
      ..@budget.defaults(),
      max_work: work.to_int64(),
    })
    assert_true(r.usage.work <= work.to_int64())
    assert_eq(r.checked_rules, r.checks.length())
    for c in r.checks {
      assert_true(c.outcome is HeldMinimal)
    }
    if r.status is @budget.CompleteInDomain {
      assert_eq(r.checked_rules.to_int64(), r.baseline_rules)
    }
  }
  let partial = @engine.discover(t, limits={
    ..@budget.defaults(),
    max_results: 1,
  })
  let replayed = compare(t, partial)
  assert_true(replayed.baseline_status is @budget.Partial(_))
  assert_true(replayed.status is @budget.CompleteInDomain)
  let none = compare(t, baseline, limits={
    ..@budget.defaults(),
    max_results: 0,
  })
  assert_true(none.status is @budget.Partial(_))
  assert_eq(none.checked_rules, 0)
}

///|
test "fresh pair scans agree with independent validators on binary snapshots" {
  for n in 0..<=3 {
    let count = 1 << (n * 2)
    for bits in 0..<count {
      let rows = Array::makei(n, i => {
        [Some("\{(bits >> (i * 2)) & 1}"), Some("\{(bits >> (i * 2 + 1)) & 1}")]
      })
      let t = sample(rows)
      let baseline = @engine.discover(
        sample([[Some("x"), Some("1")], [Some("y"), Some("2")]]),
      )
      let report = compare(t, baseline)
      for c in report.checks {
        let truth = match c.rule {
          Functional(lhs, rhs) => @verify.fd(t, lhs, rhs).holds
          Unique(columns) => @verify.unique(t, columns).holds
        }
        assert_eq(!(c.outcome is Violated(_)), truth)
        match (c.rule, c.outcome) {
          (Functional(lhs, rhs), Violated(p)) =>
            assert_true(@verify.check_pair(t, lhs, p, rhs=Some(rhs)))
          (Unique(columns), Violated(p)) =>
            assert_true(@verify.check_pair(t, columns, p))
          _ => ()
        }
      }
    }
  }
}
