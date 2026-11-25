///|
fn tuple_table(
  id : String,
  values : Array[Array[String?]],
  policy~ : @model.NullPolicy = @model.NullAsValue,
) -> @model.Table raise {
  @model.table(
    id,
    ["a", "b"].map(id => { id, name: id, }),
    values.mapi((i, cells) => { id: "r\{i}", cells, }),
    policy~,
  )
}

///|
test "tuple order, exact NULL semantics, multiplicity and ambiguous separators" {
  let source = tuple_table("s", [
    [Some("a|b"), Some("c")],
    [Some("a|b"), Some("c")],
    [Some(""), None],
    [None, Some("")],
  ])
  let target = tuple_table("t", [
    [Some("b|c"), Some("a")],
    [None, Some("")],
    [None, Some("")],
  ])
  let result = tuple_inclusion(source, ["a", "b"], target, ["b", "a"])
  assert_eq(result.holds, Some(false))
  assert_eq(result.target_unique, Some(false))
  assert_eq(result.target_distinct, Some(2))
  assert_eq(result.source_distinct, 3)
  assert_eq(result.orphan_tuples, 2)
  assert_eq(result.orphan_rows, 3)
  assert_eq(result.orphans[0].values, [Some("a|b"), Some("c")])
  assert_eq(result.orphans[0].first_source_row, "r0")
  assert_eq(result.orphans[0].source_count, 2)
  assert_eq(result.orphans[1].values, [None, Some("")])
  let reversed = tuple_inclusion(source, ["b", "a"], target, ["a", "b"])
  assert_eq(reversed.orphan_rows, result.orphan_rows)
  assert_eq(reversed.orphans[0].values, [Some("c"), Some("a|b")])
}

///|
test "empty source and target use exact set semantics" {
  let empty = tuple_table("empty", [])
  let full = tuple_table("full", [[None, Some("")]])
  let columns = ["a", "b"]
  let forward = tuple_inclusion(empty, columns, full, columns)
  assert_eq(forward.holds, Some(true))
  assert_eq(forward.source_distinct, 0)
  let reverse = tuple_inclusion(full, columns, empty, columns)
  assert_eq(reverse.holds, Some(false))
  assert_eq(reverse.target_unique, Some(true))
  assert_eq(reverse.orphan_tuples, 1)
}

///|
test "invalid mappings reject before budget evaluation" {
  let empty = tuple_table("empty", [])
  let reject = tuple_table("reject", [], policy=@model.RejectNull)
  let limits = { ..@budget.defaults(), max_candidates: 0, }
  for
    (from, to, target) in [
      ([], [], empty),
      (["a"], ["a", "b"], empty),
      (["a", "a"], ["a", "b"], empty),
      (["a", "b"], ["b", "b"], empty),
      (["missing"], ["b"], empty),
      (["a"], ["missing"], empty),
      (["a"], ["a"], reject),
    ] {
    let invalid = try {
      ignore(tuple_inclusion(empty, from, target, to, limits~))
      false
    } catch {
      @model.Invalid(_) => true
      _ => false
    }
    assert_true(invalid)
  }
}

///|
test "orphan sample limit leaves exact totals and work truncation leaves a prefix" {
  let source = tuple_table("s", [[None, None], [Some(""), None], [None, None]])
  let empty = tuple_table("t", [])
  let columns = ["a", "b"]
  let count_only = tuple_inclusion(
    source,
    columns,
    empty,
    columns,
    orphan_limit=0,
    limits={ ..@budget.defaults(), max_results: 0, },
  )
  assert_true(count_only.status is @budget.CompleteInDomain)
  assert_eq(count_only.orphan_tuples, 2)
  assert_eq(count_only.orphan_rows, 3)
  assert_true(count_only.orphans.is_empty())
  for max_work in 0..<=24 {
    let r = tuple_inclusion(source, columns, empty, columns, limits={
      ..@budget.defaults(),
      max_work: max_work.to_int64(),
    })
    assert_true(r.usage.work <= max_work.to_int64())
    assert_eq(r.orphan_rows, r.source_rows_checked)
    assert_eq(r.orphan_tuples, r.orphans.length())
    assert_eq(
      r.orphans.fold(init=0, (n, group) => n + group.source_count),
      r.orphan_rows,
    )
    if r.status is @budget.CompleteInDomain {
      assert_eq(r.orphan_rows, 3)
    } else {
      assert_true(r.holds != Some(true))
    }
  }
  let limited = tuple_inclusion(source, columns, empty, columns, limits={
    ..@budget.defaults(),
    max_results: 1,
  })
  assert_eq(limited.status, @budget.Partial("max_results"))
  assert_eq(limited.holds, Some(false))
  assert_eq(limited.source_rows_checked, 1)
}

///|
test "ordered tuple verification matches an independent nested loop on 300 cases" {
  let values = [None, Some(""), Some("x"), Some("01"), Some("1")]
  let mut seed = 20261125U
  fn next(n : UInt32) -> Int32 {
    seed = seed * 1664525U + 1013904223U
    ((seed >> 8) % n).reinterpret_as_int()
  }
  fn generated(id : String) -> @model.Table raise {
    tuple_table(
      id,
      Array::makei(next(8U), _ => [values[next(5U)], values[next(5U)]]),
    )
  }
  for _ in 0..<300 {
    let s = generated("s")
    let t = generated("t")
    let result = tuple_inclusion(s, ["b", "a"], t, ["a", "b"], orphan_limit=20)
    let target = t.rows()
    let mut missing = 0
    let seen = []
    for row in s.rows() {
      if !target.any(other => {
          row.cells[1] == other.cells[0] && row.cells[0] == other.cells[1]
        }) {
        missing += 1
        let tuple = [row.cells[1], row.cells[0]]
        if !seen.contains(tuple) {
          seen.push(tuple)
        }
      }
    }
    assert_true(result.status is @budget.CompleteInDomain)
    assert_eq(result.holds, Some(missing == 0))
    assert_eq(result.orphan_rows, missing)
    assert_eq(result.orphans.map(o => o.values), seen)
    assert_eq(result.target_unique, Some(unique(t, ["a", "b"]).holds))
  }
}
