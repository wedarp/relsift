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

///|
test "tuple scan returns the same pair as the independent nested loop" {
  let values = [None, Some(""), Some("|"), Some("a|b"), Some("é"), Some("é")]
  let mut seed = 20261125U
  fn next(bound : UInt32) -> Int32 {
    seed = seed * 1664525U + 1013904223U
    ((seed >> 8) % bound).reinterpret_as_int()
  }
  for _ in 0..<240 {
    let columns : Array[@model.Column] = ["a", "b", "c"].map(id => {
      id,
      name: id,
    })
    let rows : Array[@model.Row] = Array::makei(next(9U), i => {
      id: "r\{i}",
      cells: Array::makei(3, _ => values[next(6U)]),
    })
    let t = @model.table("t", columns, rows, policy=@model.NullAsValue)
    let sorted = t.rows()
    let meter = @budget.meter(@budget.defaults())
    for mask in 0..<8 {
      let positions = []
      for i in 0..<3 {
        if (mask & (1 << i)) != 0 {
          positions.push(i)
        }
      }
      let ids = positions.map(i => columns[i].id)
      assert_eq(
        counterexample(sorted, positions, None, meter),
        @verify.unique(t, ids).counterexample,
      )
      for rhs in 0..<3 {
        if !positions.contains(rhs) {
          assert_eq(
            counterexample(sorted, positions, Some(rhs), meter),
            @verify.fd(t, ids, columns[rhs].id).counterexample,
          )
        }
      }
    }
  }
}

///|
test "a later collision can have the earliest first row" {
  let t = sample([
    [Some("x"), Some("1")],
    [Some("y"), Some("1")],
    [Some("y"), Some("2")],
    [Some("x"), Some("2")],
  ])
  let meter = @budget.meter(@budget.defaults())
  let expected = @verify.Pair::{ first: "r0", second: "r3", }
  assert_eq(counterexample(t.rows(), [0], Some(1), meter), Some(expected))
  assert_eq(counterexample(t.rows(), [0], None, meter), Some(expected))
}

///|
test "a large unchanged key fits the work budget using a tuple scan" {
  let before = sample([[Some("old")], [Some("other")]], ids=["a"])
  let t = sample(Array::makei(4000, i => [Some("id\{i}")]), ids=["a"])
  let report = compare(t, @engine.discover(before), limits={
    ..@budget.defaults(),
    max_work: 25000L,
  })
  assert_true(report.status is @budget.CompleteInDomain)
  assert_eq(report.checked_rules, 1)
  assert_true(report.checks[0].outcome is HeldMinimal)
}
