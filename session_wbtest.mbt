///|
fn finish_session(s : Session, quota : Int32) -> Discovery raise {
  let mut calls = 0
  while s.progress() is Running {
    ignore(s.step(quota))
    calls += 1
    if calls > 10000 {
      fail("session failed to make progress")
    }
  }
  s.snapshot()
}

///|
test "seeded multivalue sessions preserve wider composite search and varying quotas" {
  let mut seed = 20261121U
  fn next() -> Int32 {
    seed = seed * 1664525U + 1013904223U
    (seed >> 8).reinterpret_as_int()
  }
  let values = [
    None,
    Some(""),
    Some("01"),
    Some("1"),
    Some("a|b"),
    Some("é"),
    Some("é"),
  ]
  for _ in 0..<120 {
    let width = next() % 5
    let height = next() % 7
    let t = snapshot(
      Array::makei(height, _ => {
        Array::makei(width, _ => values[next() % values.length()])
      }),
      width,
    )
    let s = session(t)
    while s.progress() is Running {
      ignore(s.step(1 + next() % 7))
    }
    assert_eq(s.snapshot().fds, discover(t).fds)
    assert_eq(s.snapshot().uccs, discover(t).uccs)
    assert_eq(signatures(s.snapshot()), oracle(t))
  }
}

///|
test "stepped search matches batch order, proofs, partitions and the independent oracle" {
  for n in 0..<=4 {
    for bits in 0..<(1 << (n * 2)) {
      let t = snapshot(
        Array::makei(n, r => {
          [
            Some("\{(bits >> (r * 2)) & 1}"),
            Some("\{(bits >> (r * 2 + 1)) & 1}"),
          ]
        }),
        2,
      )
      let batch = discover(t)
      for quota in [1, 3, 100] {
        let stepped = finish_session(session(t), quota)
        assert_true(stepped.status is @budget.CompleteInDomain)
        assert_eq(stepped.fds, batch.fds)
        assert_eq(stepped.uccs, batch.uccs)
        assert_eq(signatures(stepped), oracle(t))
        assert_eq(stepped.usage.candidates, batch.usage.candidates)
        assert_eq(stepped.usage.partitions, batch.usage.partitions)
        assert_eq(stepped.usage.cache_hits, batch.usage.cache_hits)
        for f in stepped.fds {
          assert_true(verify_fd(t, f))
        }
        for k in stepped.uccs {
          assert_true(verify_ucc(t, k))
        }
      }
    }
  }
}

///|
test "zero quota is inert and negative quotas leave the cursor unchanged" {
  let t = snapshot([[Some("x")], [Some("y")]], 1)
  let s = session(t)
  let before = s.snapshot()
  assert_true(s.step(0) is Running)
  assert_eq(s.snapshot(), before)
  let rejected = try {
    ignore(s.step(-1))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  assert_eq(s.snapshot(), before)
  let done = finish_session(s, 1)
  assert_true(s.step(100) is Finished)
  assert_eq(s.snapshot(), done)
}

///|
test "snapshot arrays cannot mutate ongoing or completed session state" {
  let t = snapshot([[Some("x"), Some("1")], [Some("y"), Some("2")]], 2)
  let s = session(t)
  while s.snapshot().fds.is_empty() {
    ignore(s.step(1))
  }
  let exposed = s.snapshot()
  exposed.fds[0].lhs.push("forged")
  exposed.fds[0].deletions.clear()
  exposed.fds.clear()
  let done = finish_session(s, 1)
  let batch = discover(t)
  assert_eq(done.fds, batch.fds)
  assert_eq(done.uccs, batch.uccs)
  done.uccs[0].columns.clear()
  done.uccs[0].deletions.clear()
  done.uccs.clear()
  assert_eq(s.snapshot().uccs, batch.uccs)
}

///|
test "hard budgets remain cumulative across yields and exhausted sessions are terminal" {
  let t = snapshot([[Some("x"), Some("1")], [Some("y"), Some("2")]], 2)
  for
    limits in [
      { ..@budget.defaults(), max_candidates: 2, },
      { ..@budget.defaults(), max_results: 1, },
      { ..@budget.defaults(), max_work: 0L, },
    ] {
    let s = session(t, limits~)
    let result = finish_session(s, 1)
    assert_true(s.progress() is BudgetExhausted(_))
    assert_true(result.status is @budget.Partial(_))
    assert_true(result.usage.candidates <= limits.max_candidates)
    assert_true(result.usage.work <= limits.max_work)
    assert_true(result.usage.results <= limits.max_results)
    ignore(s.step(1000))
    assert_eq(s.snapshot(), result)
    for f in result.fds {
      assert_true(verify_fd(t, f))
    }
    for k in result.uccs {
      assert_true(verify_ucc(t, k))
    }
  }
}

///|
test "declared domains, zero columns and nullable lexical distinctions survive yielding" {
  let t = snapshot(
    [[None, Some("")], [Some(""), Some("01")], [Some("é"), Some("é")]],
    2,
  )
  for max_lhs in 0..<=2 {
    for max_ucc_width in 0..<=2 {
      let limits = { ..@budget.defaults(), max_lhs, max_ucc_width, }
      let stepped = finish_session(session(t, limits~), 1)
      let batch = discover(t, limits~)
      assert_eq(stepped.fds, batch.fds)
      assert_eq(stepped.uccs, batch.uccs)
    }
  }
  for cells in [[], [[]], [[], []]] {
    let t = snapshot(cells, 0)
    let stepped = finish_session(session(t), 1)
    assert_eq(signatures(stepped), oracle(t))
    assert_true(stepped.fd_complete && stepped.ucc_complete)
  }
}
