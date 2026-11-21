///|
fn diagnostic_table() -> @model.Table raise {
  @model.table(
    "t",
    ["a", "b"].map(id => { id, name: id, }),
    [
      { id: "r1", cells: [Some("x"), Some("p")], },
      { id: "r2", cells: [Some("x"), Some("p")], },
      { id: "r3", cells: [Some("x"), Some("q")], },
      { id: "r4", cells: [Some("y"), None], },
      { id: "r5", cells: [Some("y"), Some("")], },
    ],
    policy=@model.NullAsValue,
  )
}

///|
test "FD diagnostics count exact conflicting row pairs and groups" {
  let t = diagnostic_table()
  let report = diagnose_fd(t, ["a"], "b")
  assert_eq(report.status, @budget.CompleteInDomain)
  assert_eq(report.holds, Some(false))
  assert_eq(report.conflicting_groups, 2)
  assert_eq(report.violating_pairs, 3L)
  assert_eq(report.groups[0].rows, ["r1", "r2", "r3"])
  assert_eq(report.groups[0].violating_pairs, 2L)
  for group in report.groups {
    assert_true(check_pair(t, ["a"], group.witness, rhs=Some("b")))
  }
  let rows = t.rows()
  let mut direct = 0L
  for i in 0..<rows.length() {
    for j in (i + 1)..<rows.length() {
      if rows[i].cells[0] == rows[j].cells[0] &&
        rows[i].cells[1] != rows[j].cells[1] {
        direct += 1L
      }
    }
  }
  assert_eq(report.violating_pairs, direct)
}

///|
test "unique diagnostics preserve multiplicity and empty-set collisions" {
  let t = diagnostic_table()
  let full = diagnose_unique(t, ["a", "b"])
  assert_eq(full.holds, Some(false))
  assert_eq(full.collision_groups, 1)
  assert_eq(full.excess_rows, 1)
  assert_eq(full.collision_pairs, 1L)
  assert_eq(full.groups[0].rows, ["r1", "r2"])
  let empty = diagnose_unique(t, [])
  assert_eq(empty.collision_groups, 1)
  assert_eq(empty.collision_pairs, 10L)
  assert_eq(empty.excess_rows, 4)
}

///|
test "orphan diagnostics expose distinct values and all source row IDs" {
  let source = diagnostic_table()
  let target = @model.table(
    "target",
    [{ id: "code", name: "code", }],
    [{ id: "t1", cells: [Some("p")], }, { id: "t2", cells: [Some("p")], }],
    policy=@model.NullAsValue,
  )
  let report = diagnose_inclusion(source, "b", target, "code")
  assert_eq(report.holds, Some(false))
  assert_eq(report.target_unique, Some(false))
  assert_eq(report.orphan_values, 3)
  assert_eq(report.orphan_rows, 3)
  assert_eq(report.groups.map(g => g.source_rows[0]), ["r3", "r4", "r5"])
  assert_eq(
    report.orphan_values,
    inclusion(source, "b", target, "code").orphan_count,
  )
}

///|
test "bounded diagnostics never call incomplete scans valid" {
  let t = diagnostic_table()
  for work in 0..<100 {
    let limits = { ..@budget.defaults(), max_work: work.to_int64(), }
    let fd_report = diagnose_fd(t, ["a"], "b", limits~)
    let key_report = diagnose_unique(t, ["a"], limits~)
    assert_true(fd_report.usage.work <= work.to_int64())
    assert_true(key_report.usage.work <= work.to_int64())
    if fd_report.status is @budget.Partial(_) {
      assert_true(fd_report.holds != Some(true))
    }
    if key_report.status is @budget.Partial(_) {
      assert_true(key_report.holds != Some(true))
    }
    for group in fd_report.groups {
      assert_true(check_pair(t, ["a"], group.witness, rhs=Some("b")))
    }
  }
  let truncated = diagnose_unique(t, [], limits={
    ..@budget.defaults(),
    max_results: 0,
  })
  assert_eq(truncated.holds, Some(false))
  assert_true(truncated.groups.is_empty())
  assert_true(truncated.status is @budget.Partial(_))
}

///|
test "diagnostic pair counts agree with exhaustive row-pair scans" {
  for height in 0..<=4 {
    for bits in 0..<(1 << (height * 2)) {
      let t = @model.table(
        "t",
        ["a", "b"].map(id => { id, name: id, }),
        Array::makei(height, r => {
          id: "r\{r}",
          cells: Array::makei(2, c => {
            Some(if (bits & (1 << (r * 2 + c))) == 0 { "x" } else { "y" })
          }),
        }),
      )
      let rows = t.rows()
      let mut violations = 0L
      let mut collisions = 0L
      for i in 0..<height {
        for j in (i + 1)..<height {
          if rows[i].cells[0] == rows[j].cells[0] {
            collisions += 1L
            if rows[i].cells[1] != rows[j].cells[1] {
              violations += 1L
            }
          }
        }
      }
      let f = diagnose_fd(t, ["a"], "b")
      let u = diagnose_unique(t, ["a"])
      assert_eq(f.violating_pairs, violations)
      assert_eq(u.collision_pairs, collisions)
      assert_eq(f.holds, Some(fd(t, ["a"], "b").holds))
      assert_eq(u.holds, Some(unique(t, ["a"]).holds))
    }
  }
}
