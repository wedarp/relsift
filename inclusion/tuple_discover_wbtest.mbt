///|
fn tuple_table(
  id : String,
  columns : Array[String],
  rows : Array[Array[String?]],
  policy~ : @model.NullPolicy = @model.NullAsValue,
) -> @model.Table raise {
  @model.table(
    id,
    columns.map(id => { id, name: id, }),
    rows.mapi((i, cells) => { id: "r\{i}", cells, }),
    policy~,
  )
}

///|
fn tuples_at(
  rows : Array[@model.Row],
  positions : Array[Int32],
) -> Array[Array[String?]] {
  rows.map(row => positions.map(p => row.cells[p]))
}

///|
fn count_distinct(tuples : Array[Array[String?]]) -> Int32 {
  let values = []
  for tuple in tuples {
    if !values.contains(tuple) {
      values.push(tuple)
    }
  }
  values.length()
}

///|
/// Enumerate all mappings and compare raw tuples by direct scans.
fn tuple_oracle(
  tables : Array[@model.Table],
  max_width : Int32,
) -> Array[TupleInd] {
  let ordered = tables.copy()
  ordered.sort_by((a, b) => a.id.lexical_compare(b.id))
  let expected = []
  for source in ordered {
    for target in ordered {
      if source.id == target.id {
        continue
      }
      let from_columns = source.columns().map(c => c.id)
      let to_columns = target.columns().map(c => c.id)
      let source_rows = source.rows()
      let target_rows = target.rows()
      fn enumerate(
        from : Array[Int32],
        to : Array[Int32],
        start : Int32,
        width : Int32,
      ) {
        if from.length() == width {
          let left = tuples_at(source_rows, from)
          let right = tuples_at(target_rows, to)
          if left.all(tuple => right.contains(tuple)) {
            let distinct = count_distinct(right)
            expected.push({
              source_table: source.id,
              source_columns: from.map(i => from_columns[i]),
              target_table: target.id,
              target_columns: to.map(i => to_columns[i]),
              source_distinct: count_distinct(left),
              target_distinct: distinct,
              target_unique: distinct == right.length(),
            })
          }
          return
        }
        for i in start..<from_columns.length() {
          for j in 0..<to_columns.length() {
            if !to.contains(j) {
              enumerate(from + [i], to + [j], i + 1, width)
            }
          }
        }
      }
      let max_width = Int32::min(
        max_width,
        Int32::min(from_columns.length(), to_columns.length()),
      )
      for width in 2..<=max_width {
        enumerate([], [], 0, width)
      }
    }
  }
  expected
}

///|
test "tuple discovery keeps positional permutations and exact values distinct" {
  let source = tuple_table("orders", ["region", "sku"], [
    [Some("a|b"), Some("c")],
    [Some("a"), Some("b|c")],
    [None, Some("")],
    [None, Some("")],
  ])
  let target = tuple_table("stock", ["product", "warehouse"], [
    [Some("c"), Some("a|b")],
    [Some("b|c"), Some("a")],
    [Some(""), None],
    [Some("01"), Some("extra")],
  ])
  let report = discover_tuples([target, source])
  assert_eq(report.status, @budget.CompleteInDomain)
  assert_eq(report.relations, [
    {
      source_table: "orders",
      source_columns: ["region", "sku"],
      target_table: "stock",
      target_columns: ["warehouse", "product"],
      source_distinct: 3,
      target_distinct: 4,
      target_unique: true,
    },
  ])
  assert_eq(report.null_policy, Some(@model.NullAsValue))
  let r = report.relations[0]
  let checked = @verify.tuple_inclusion(
    source,
    r.source_columns,
    target,
    r.target_columns,
  )
  assert_eq(checked.holds, Some(true))
  assert_eq(checked.target_distinct, Some(4))
  assert_eq(checked.source_distinct, 3)
  assert_eq(checked.target_unique, Some(true))
}

///|
test "unary inclusion does not imply the joint positional relation" {
  let source = tuple_table("a", ["a", "b"], [
    [Some("é"), Some("01")],
    [Some("é"), Some("1")],
  ])
  let target = tuple_table("b", ["x", "y"], [
    [Some("é"), Some("1")],
    [Some("é"), Some("01")],
  ])
  assert_eq(discover([source, target]).relations.length(), 4)
  let result = discover_tuples([source, target])
  assert_eq(result.status, @budget.CompleteInDomain)
  assert_eq(result.relations.length(), 0)
  assert_true(result.tuple_checks > 0)
  assert_eq(
    @verify.tuple_inclusion(source, ["a", "b"], target, ["x", "y"]).orphan_tuples,
    2,
  )
}

///|
test "failed binary projection prunes a triple with successful unary positions" {
  let source = tuple_table("a", ["a", "b", "c"], [
    [Some("0"), Some("0"), Some("0")],
    [Some("0"), Some("1"), Some("0")],
    [Some("1"), Some("0"), Some("1")],
    [Some("1"), Some("1"), Some("1")],
  ])
  let target = tuple_table("b", ["a", "b", "c"], [
    [Some("0"), Some("0"), Some("0")],
    [Some("0"), Some("1"), Some("1")],
    [Some("1"), Some("0"), Some("0")],
    [Some("1"), Some("1"), Some("1")],
  ])
  let result = discover_tuples([source, target], options={
    ..tuple_defaults(),
    max_width: 3,
  })
  assert_eq(result.relations, tuple_oracle([source, target], 3))
  assert_true(result.projection_pruned > 0)
  assert_true(result.relations.any(r => r.source_columns.length() == 3))
}

///|
test "unique-target output does not discard useful nonunique prefixes" {
  let entries = Array::makei(8, r => {
    Array::makei(3, c => Some("\{(r >> c) & 1}"))
  })
  let tables = [
    tuple_table("a", ["a", "b", "c"], entries),
    tuple_table("b", ["a", "b", "c"], entries),
  ]
  let options = { ..tuple_defaults(), max_width: 3, }
  let full = discover_tuples(tables, options~)
  let limited = discover_tuples(tables, options={
    ..options,
    target_unique_only: true,
  })
  assert_eq(limited.relations, full.relations.filter(r => r.target_unique))
  assert_eq(limited.relations.length(), 12)
  assert_true(limited.relations.all(r => r.source_columns.length() == 3))
  let uncached = discover_tuples(tables, options={
    ..options,
    max_cached_projections: 0,
  })
  assert_eq(uncached.relations, full.relations)
  assert_eq(uncached.cached_projections, 0)
  assert_eq(uncached.usage.cache_hits, 0L)
  assert_true(full.usage.cache_hits > 0L)
  assert_true(uncached.projections_built > full.projections_built)
  assert_true(uncached.usage.work > full.usage.work)
}

///|
test "tuple discovery handles empty domains, malformed options and incompatible policies" {
  let empty = tuple_table("a", ["a", "b"], [])
  let nonempty = tuple_table("b", ["a", "b"], [
    [Some("same"), Some("same")],
    [Some("same"), Some("same")],
  ])
  let result = discover_tuples([empty, nonempty])
  assert_eq(result.relations.length(), 2)
  assert_true(
    result.relations.all(r => {
      r.source_distinct == 0 && r.target_distinct == 1 && !r.target_unique
    }),
  )
  let narrow = tuple_table("one", ["c"], [[Some("1")]])
  let vacuous = discover_tuples([nonempty, narrow], limits={
    ..@budget.defaults(),
    max_work: 0L,
  })
  assert_eq(vacuous.status, @budget.CompleteInDomain)
  assert_eq(vacuous.usage.candidates, 0)
  assert_true(
    (Some(discover_tuples([empty, empty])) catch { _ => None }) is None,
  )
  let strict = tuple_table("strict", ["a", "b"], [], policy=@model.RejectNull)
  assert_true(
    (Some(discover_tuples([empty, strict])) catch { _ => None }) is None,
  )
  assert_true(
    (Some(discover_tuples([], options={ ..tuple_defaults(), max_width: 1, })) catch {
      _ => None
    })
    is None,
  )
  assert_true(
    (Some(
      discover_tuples([], options={
        ..tuple_defaults(),
        max_cached_projections: -1,
      }),
    ) catch {
      _ => None
    })
    is None,
  )
}

///|
test "budgets retain only a stable prefix of proved mappings" {
  let tables = [
    tuple_table("a", ["a", "b", "c"], [[Some("x"), Some("x"), Some("x")]]),
    tuple_table("b", ["a", "b", "c"], [[Some("x"), Some("x"), Some("x")]]),
  ]
  let options = { ..tuple_defaults(), max_width: 3, }
  let complete = discover_tuples(tables, options~)
  assert_eq(complete.status, @budget.CompleteInDomain)
  for
    limits in [
      { ..@budget.defaults(), max_results: 0, },
      { ..@budget.defaults(), max_results: 3, },
      { ..@budget.defaults(), max_candidates: 15, },
      { ..@budget.defaults(), max_work: 0L, },
      { ..@budget.defaults(), max_work: complete.usage.work / 2L, },
    ] {
    let partial = discover_tuples(tables, options~, limits~)
    assert_true(partial.status is @budget.Partial(_))
    assert_eq(
      partial.relations,
      Array::makei(partial.relations.length(), i => complete.relations[i]),
    )
    assert_eq(partial.relations.length(), partial.usage.results)
    assert_true(partial.usage.work <= limits.max_work)
    assert_true(partial.usage.candidates <= limits.max_candidates)
  }
}

///|
test "seeded composite discovery agrees with all ordered mappings across widths" {
  let mut seed = 512021U
  fn next() -> Int32 {
    seed = seed * 1664525U + 1013904223U
    (seed >> 16).reinterpret_as_int()
  }
  let raw = [
    None,
    Some(""),
    Some("1"),
    Some("01"),
    Some("x|y"),
    Some("é"),
    Some("é"),
  ]
  fn generated(id : String, alphabet : Int32) -> @model.Table raise {
    let width = 2 + next() % 3
    let rows = Array::makei(next() % 6, _ => {
      Array::makei(width, _ => raw[next() % alphabet])
    })
    tuple_table(id, Array::makei(width, i => "c\{i}"), rows)
  }
  for i in 0..<120 {
    let alphabet = 2 + i % 6
    let a = generated("a", alphabet)
    let b = generated("b", alphabet)
    let tables = if i % 4 == 0 {
      [b, generated("z", alphabet), a]
    } else {
      [b, a]
    }
    for max_width in [2, 3, 4] {
      let options = { ..tuple_defaults(), max_width, }
      let result = discover_tuples(tables, options~)
      assert_eq(result.status, @budget.CompleteInDomain)
      assert_eq(result.relations, tuple_oracle(tables, max_width))
      let reordered = tables.copy()
      reordered.rev_in_place()
      assert_eq(result, discover_tuples(reordered, options~))
    }
  }
}
