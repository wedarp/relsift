///|
fn signatures(rules : Array[Rule]) -> Array[(Array[String], String)] {
  rules.map(rule => (rule.lhs, rule.rhs))
}

///|
fn assert_equivalent(comparison : TheoryComparison) -> Unit raise {
  assert_eq(comparison.status, @budget.CompleteInDomain)
  assert_true(comparison.left_to_right is EntailsAll)
  assert_true(comparison.right_to_left is EntailsAll)
}

///|
test "minimal cover shortens composite rules, drops duplicates, and preserves constants" {
  let original = theory(["a", "b", "c", "d", "e", "f"], [
    { lhs: ["a"], rhs: "b", },
    { lhs: ["b"], rhs: "c", },
    { lhs: ["a"], rhs: "c", },
    { lhs: ["a", "d"], rhs: "c", },
    { lhs: ["c", "d"], rhs: "e", },
    { lhs: ["d"], rhs: "c", },
    { lhs: [], rhs: "f", },
  ])
  let result = original.minimal_cover()
  assert_eq(result.status, @budget.CompleteInDomain)
  assert_eq(signatures(result.rules), [
    ([], "f"),
    (["a"], "b"),
    (["b"], "c"),
    (["d"], "c"),
    (["d"], "e"),
  ])
  assert_eq(result.usage.results, result.edits.length())
  assert_eq(result.edits.length(), 3)
  assert_true(result.edits.any(edit => edit is RemovedColumn(_, "c")))
  let minimized = theory(original.columns(), result.rules)
  let audit = original.audit_cover(minimized)
  assert_equivalent(audit.comparison)
  assert_true(audit.minimality is Irreducible)
  assert_eq(audit.status, @budget.CompleteInDomain)
  let reverse = original.rules()
  reverse.rev_in_place()
  assert_eq(
    signatures(theory(original.columns(), reverse).minimal_cover().rules),
    signatures(result.rules),
  )
  assert_eq(theory([], []).minimal_cover().rules.length(), 0)
}

///|
test "comparison separates each direction and rejects forged or out-of-schema claims" {
  let left = theory(["a", "b", "c"], [{ lhs: ["a"], rhs: "b", }])
  let right = theory(["c", "b", "a"], [{ lhs: ["a"], rhs: "c", }])
  let result = left.compare(right)
  assert_eq(result.status, @budget.CompleteInDomain)
  guard result.left_to_right is Separated(forward) else {
    fail("missing forward witness")
  }
  guard result.right_to_left is Separated(backward) else {
    fail("missing backward witness")
  }
  assert_eq(forward.agreement, ["a", "b"])
  assert_eq(backward.agreement, ["a", "c"])
  assert_true(left.verify_separation(right, forward))
  assert_true(right.verify_separation(left, backward))
  assert_false(
    left.verify_separation(right, { ..forward, agreement: ["a", "b", "c"], }),
  )
  assert_false(
    left.verify_separation(right, {
      ..forward,
      rule: { lhs: ["b"], rhs: "c", },
    }),
  )
  let bounded = left.compare(right, limits={
    ..@budget.defaults(),
    max_results: 1,
  })
  assert_eq(bounded.status, @budget.Partial("max_results"))
  assert_true(bounded.left_to_right is Separated(_))
  assert_true(bounded.right_to_left is Unchecked)
  let foreign = theory(["a", "b"], [])
  assert_true((Some(left.compare(foreign)) catch { _ => None }) is None)
}

///|
test "cover audit independently reports both kinds of reducibility" {
  let redundant = theory(["a", "b", "c"], [
    { lhs: ["a"], rhs: "c", },
    { lhs: ["a"], rhs: "b", },
    { lhs: ["b"], rhs: "c", },
  ])
  let report = redundant.audit_cover(redundant)
  assert_equivalent(report.comparison)
  guard report.minimality is Reducible(reduction) else {
    fail("missed redundant premise")
  }
  assert_eq(reduction.rule_index, 0)
  assert_true(reduction.removed_column is None)
  assert_true(redundant.verify_reduction(reduction))
  assert_false(
    redundant.verify_reduction({
      ..reduction,
      proof: [{ rule_index: 0, derived: "c", }],
    }),
  )

  let extraneous = theory(["a", "b", "c"], [
    { lhs: ["a", "b"], rhs: "c", },
    { lhs: ["a"], rhs: "b", },
  ])
  let report = extraneous.audit_cover(extraneous)
  guard report.minimality is Reducible(reduction) else {
    fail("missed extraneous column")
  }
  assert_true(reduction.removed_column is Some("b"))
  assert_true(extraneous.verify_reduction(reduction))
  assert_false(
    extraneous.verify_reduction({ ..reduction, removed_column: Some("a"), }),
  )
  let bounded = extraneous.audit_cover(extraneous, limits={
    ..@budget.defaults(),
    max_candidates: report.comparison.usage.candidates,
  })
  assert_equivalent(bounded.comparison)
  assert_true(bounded.minimality is MinimalityUnchecked)
  assert_eq(bounded.status, @budget.Partial("max_candidates"))
}

///|
test "every interrupted cover remains equivalent, including interruption between edits" {
  let original = theory(["a", "b", "c", "d"], [
    { lhs: ["a"], rhs: "b", },
    { lhs: ["b"], rhs: "c", },
    { lhs: ["a"], rhs: "c", },
    { lhs: ["a", "b"], rhs: "d", },
  ])
  let complete = original.minimal_cover()
  for work in 0L..<complete.usage.work {
    let partial = original.minimal_cover(limits={
      ..@budget.defaults(),
      max_work: work,
    })
    assert_eq(partial.status, @budget.Partial("max_work"))
    assert_true(partial.usage.work <= work)
    assert_eq(partial.usage.results, partial.edits.length())
    assert_equivalent(
      original.compare(theory(original.columns(), partial.rules)),
    )
  }
  for cap in 0..<complete.edits.length() {
    let partial = original.minimal_cover(limits={
      ..@budget.defaults(),
      max_results: cap,
    })
    assert_eq(partial.status, @budget.Partial("max_results"))
    assert_eq(partial.edits.length(), cap)
    assert_equivalent(
      original.compare(theory(original.columns(), partial.rules)),
    )
  }
}

///|
fn each_small_theory(
  visit : (Array[String], Array[Array[String]], Array[Rule]) -> Unit raise,
) -> Unit raise {
  let columns = ["a", "b", "c", "d", "e"]
  let sets = Array::makei(1 << columns.length(), mask => {
    let subset = []
    for i, col in columns {
      if (mask & (1 << i)) != 0 {
        subset.push(col)
      }
    }
    subset
  })
  let mut state = 836359U
  for _ in 0..<120 {
    let rules : Array[Rule] = []
    for lhs in sets {
      for rhs in columns {
        if !lhs.contains(rhs) {
          state = state * 1664525U + 1013904223U
          if (state >> 24) % 11U == 0U {
            rules.push({ lhs, rhs, })
          }
        }
      }
    }
    visit(columns, sets, rules)
  }
}

///|
test "seeded covers preserve every closure and pass independent irreducibility checks" {
  each_small_theory(fn(columns, sets, rules) raise {
    let source = theory(columns, rules)
    let result = source.minimal_cover()
    assert_eq(result.status, @budget.CompleteInDomain)
    let minimized = theory(columns, result.rules)
    let audit = source.audit_cover(minimized)
    assert_equivalent(audit.comparison)
    assert_true(audit.minimality is Irreducible)
    for lhs in sets {
      assert_eq(
        reference_closure(lhs, result.rules),
        reference_closure(lhs, rules),
      )
    }
  })
}
