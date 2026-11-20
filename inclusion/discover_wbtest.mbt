///|
fn one(id : String, values : Array[String?]) -> @model.Table raise {
  @model.table(
    id,
    [{ id: "c", name: "c", }],
    values.mapi((i, v) => { id: "r\{i}", cells: [v], }),
    policy=@model.NullAsValue,
  )
}

///|
test "inclusion discovery agrees with independent sets, target duplicates and orphans" {
  let tables = [
    one("source", [Some("P1"), Some("P2")]),
    one("target", [Some("P1"), Some("P2"), Some("P2")]),
    one("empty", []),
    one("null", [None]),
    one("empty_string", [Some("")]),
  ]
  let result = discover(tables)
  assert_eq(result.status, @budget.CompleteInDomain)
  for s in tables {
    for t in tables {
      if s.id == t.id {
        continue
      }
      let reference = @verify.inclusion(s, "c", t, "c")
      let matches = result.relations.filter(r => {
        r.source_table == s.id && r.target_table == t.id
      })
      assert_eq(matches.length(), if reference.holds { 1 } else { 0 })
      for r in matches {
        assert_eq(r.source_distinct, reference.source_distinct)
        assert_eq(r.target_distinct, reference.target_distinct)
        assert_eq(r.target_unique, reference.target_unique)
      }
    }
  }
  let invalid = @verify.inclusion(
    one("s", [Some("P9"), Some("P8"), Some("P9")]),
    "c",
    tables[1],
    "c",
    orphan_limit=1,
  )
  assert_eq(invalid.orphan_count, 2)
  assert_eq(invalid.orphans_omitted, 1)
  assert_true(!invalid.holds)
  assert_eq(discover(tables), discover(tables.rev()))
}

///|
test "inclusion budget truncation retains only independently valid relations" {
  let tables = [
    one("a", [None, Some("")]),
    one("b", [Some(""), None, None]),
    one("c", []),
  ]
  for work in 0..<100 {
    let result = discover(tables, limits={
      ..@budget.defaults(),
      max_work: work.to_int64(),
    })
    for relation in result.relations {
      let s = tables[tables
        .search_by(t => t.id == relation.source_table)
        .unwrap()]
      let t = tables[tables
        .search_by(t => t.id == relation.target_table)
        .unwrap()]
      assert_true(@verify.inclusion(s, "c", t, "c").holds)
    }
    assert_true(result.usage.work <= work.to_int64())
  }
  assert_true(
    try {
      ignore(discover([tables[0], tables[0]]))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "seeded multitable inclusion differential and policy mismatch" {
  let mut seed = 20261120U
  fn next() -> UInt32 {
    seed = seed * 1664525U + 1013904223U
    seed
  }
  let values = [None, Some(""), Some("01"), Some("1"), Some("é"), Some("é")]
  for _ in 0..<100 {
    let tables = Array::makei(3, i => {
      one(
        "t\{i}",
        Array::makei((next() % 6U).reinterpret_as_int(), _ => {
          values[(next() % 6U).reinterpret_as_int()]
        }),
      )
    })
    let actual = discover(tables)
    assert_eq(actual.status, @budget.CompleteInDomain)
    for s in tables {
      for t in tables {
        if s.id != t.id {
          assert_eq(
            actual.relations.any(r => {
              r.source_table == s.id && r.target_table == t.id
            }),
            @verify.inclusion(s, "c", t, "c").holds,
          )
        }
      }
    }
  }
  let reject = @model.table("reject", [{ id: "c", name: "c", }], [])
  assert_true(
    try {
      ignore(discover([reject, one("equal", [])]))
      false
    } catch {
      _ => true
    },
  )
}
