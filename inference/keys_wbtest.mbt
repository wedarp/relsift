///|
test "schema key enumeration finds alternatives and verifies both forms of evidence" {
  let compiled = theory(["e", "c", "b", "d", "a"], [
    { lhs: ["a"], rhs: "b", },
    { lhs: ["b"], rhs: "a", },
    { lhs: ["b", "c"], rhs: "d", },
    { lhs: [], rhs: "e", },
  ])
  let result = compiled.schema_keys()
  assert_eq(result.status, @budget.CompleteInDomain)
  assert_eq(result.keys.map(key => key.columns), [["a", "c"], ["b", "c"]])
  for key in result.keys {
    assert_true(compiled.verify_schema_key(key))
    assert_false(compiled.verify_schema_key({ ..key, proof: [], }))
    assert_false(
      compiled.verify_schema_key({
        ..key,
        deletions: [key.deletions[0], key.deletions[0]],
      }),
    )
  }
  let bounded = compiled.schema_keys(limits={
    ..@budget.defaults(),
    max_lhs: 1,
  })
  assert_eq(bounded.status, @budget.CompleteInDomain)
  assert_eq(bounded.max_width, 1)
  assert_eq(bounded.keys.length(), 0)
  let partial = compiled.schema_keys(limits={
    ..@budget.defaults(),
    max_results: 1,
  })
  assert_eq(partial.status, @budget.Partial("max_results"))
  assert_eq(partial.keys.length(), 1)
  assert_true(compiled.verify_schema_key(partial.keys[0]))
  let no_work = compiled.schema_keys(limits={
    ..@budget.defaults(),
    max_work: 0L,
  })
  assert_eq(no_work.status, @budget.Partial("max_work"))
  assert_eq(no_work.keys.length(), 0)
}

///|
test "schema key boundaries cover empty theory, constants, and mandatory columns" {
  let empty = theory([], [])
  let empty_key = empty.schema_keys().keys[0]
  assert_eq(empty_key.columns, [])
  assert_true(empty.verify_schema_key(empty_key))
  let fixed = theory(["a", "b"], [
    { lhs: [], rhs: "a", },
    { lhs: ["a"], rhs: "b", },
  ])
  let all_fixed = fixed.schema_keys(limits={
    ..@budget.defaults(),
    max_lhs: 0,
    max_candidates: 1,
  })
  assert_eq(all_fixed.status, @budget.CompleteInDomain)
  assert_eq(all_fixed.keys.map(key => key.columns), [[]])
  assert_true(fixed.verify_schema_key(all_fixed.keys[0]))
  let bare = theory(["a", "b"], [])
  let result = bare.schema_keys()
  assert_eq(result.keys.map(key => key.columns), [["a", "b"]])
  assert_true(bare.verify_schema_key(result.keys[0]))
  let narrow = bare.schema_keys(limits={
    ..@budget.defaults(),
    max_lhs: 1,
    max_candidates: 0,
  })
  assert_eq(narrow.status, @budget.CompleteInDomain)
  assert_eq(narrow.keys.length(), 0)
}

///|
test "seeded schema key search matches exhaustive subsets and their strict subsets" {
  each_small_theory(fn(columns, subsets, rules) raise {
    let compiled = theory(columns, rules)
    let superkeys = subsets.filter(lhs => {
      reference_closure(lhs, rules).length() == columns.length()
    })
    for width in 0..<=columns.length() {
      let expected = superkeys.filter(lhs => {
        lhs.length() <= width &&
        !superkeys.any(parent => {
          parent.length() < lhs.length() && parent.all(col => lhs.contains(col))
        })
      })
      let found = compiled.schema_keys(limits={
        ..@budget.defaults(),
        max_lhs: width,
      })
      assert_eq(found.status, @budget.CompleteInDomain)
      assert_eq(found.keys.length(), expected.length())
      for key in found.keys {
        assert_true(expected.contains(key.columns))
        assert_true(compiled.verify_schema_key(key))
      }
    }
  })
}
