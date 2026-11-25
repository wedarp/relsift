///|
fn order_theory() -> Theory raise {
  theory(["warehouse", "product", "name", "line", "currency", "order"], [
    { lhs: ["order", "line"], rhs: "product", },
    { lhs: ["product"], rhs: "name", },
    { lhs: ["name"], rhs: "product", },
    { lhs: [], rhs: "currency", },
  ])
}

///|
test "inference projects a composite proof and independently checks a refutation" {
  let compiled = order_theory()
  let result = compiled.closure(["order", "line"])
  assert_eq(result.status, @budget.CompleteInDomain)
  assert_eq(result.attributes, ["currency", "line", "name", "order", "product"])
  assert_eq(result.steps.map(step => step.rule_index), [3, 0, 1])
  assert_true(compiled.verify_trace(result))
  guard compiled.explain(result, "name") is Some(proof) else {
    fail("missing proof")
  }
  assert_eq(proof.map(step => step.rule_index), [0, 1])
  assert_true(compiled.verify_entailment(result.seeds, "name", proof))
  assert_false(compiled.verify_entailment(["line"], "name", proof))
  assert_true(compiled.explain(result, "order") is Some([]))
  assert_true(compiled.explain(result, "warehouse") is None)
  let query = compiled.implies(["product"], "warehouse")
  guard query.outcome is Refuted(agreement) else {
    fail("missing counterexample")
  }
  assert_eq(agreement, ["currency", "name", "product"])
  assert_true(compiled.verify_counterexample(query.lhs, query.rhs, agreement))
  assert_false(
    compiled.verify_counterexample(query.lhs, query.rhs, ["product", "currency"]),
  )
  assert_false(
    compiled.verify_counterexample(query.lhs, query.rhs, ["product", "name"]),
  )
  assert_false(
    compiled.verify_counterexample(
      query.lhs,
      query.rhs,
      agreement + ["warehouse"],
    ),
  )
}

///|
test "closure budgets retain sound prefixes, including zero-budget seed entailment" {
  let compiled = order_theory()
  let limits = @budget.defaults()
  for
    (bounded, reason) in [
      ({ ..limits, max_work: 0L, }, "max_work"),
      ({ ..limits, max_candidates: 1, }, "max_candidates"),
      ({ ..limits, max_results: 1, }, "max_results"),
    ] {
    let result = compiled.closure(["line", "order"], limits=bounded)
    assert_eq(result.status, @budget.Partial(reason))
    assert_true(compiled.verify_trace(result))
    assert_eq(result.usage.results, result.steps.length())
    assert_true(
      compiled.implies(["line", "order"], "name", limits=bounded).outcome
      is Undetermined,
    )
  }
  let seed = compiled.implies(["order"], "order", limits={
    ..limits,
    max_work: 0L,
  })
  assert_true(seed.outcome is Entailed([]))
  assert_eq(seed.status, @budget.Partial("max_work"))
  let constant = compiled.implies(["line", "order"], "currency", limits={
    ..limits,
    max_results: 1,
  })
  assert_eq(constant.status, @budget.Partial("max_results"))
  guard constant.outcome is Entailed(proof) else {
    fail("expected a proved constant despite the incomplete closure")
  }
  assert_true(compiled.verify_entailment(constant.lhs, constant.rhs, proof))
  assert_true(compiled.implies([], "product").outcome is Refuted(["currency"]))
  let empty = theory([], [])
  assert_eq(empty.closure([]).attributes, [])
}

///|
test "theory owns its inputs and rejects misspelled or duplicate declarations" {
  let columns = ["é", "é", "δ"]
  let rules : Array[Rule] = [{ lhs: ["é"], rhs: "δ", }]
  let compiled = theory(columns, rules)
  columns[0] = "changed"
  rules[0].lhs[0] = "changed"
  compiled.rules()[0].lhs[0] = "changed again"
  assert_eq(compiled.closure(["é"]).attributes, ["é", "δ"])
  assert_eq(compiled.closure(["é"]).attributes, ["é"])
  assert_true(
    (Some(compiled.closure(["é", "é"])) catch { _ => None }) is None,
  )
  assert_true(
    (Some(compiled.implies([], "changed")) catch { _ => None }) is None,
  )
  assert_true((Some(theory(["a", "a"], [])) catch { _ => None }) is None)
  assert_true((Some(theory([""], [])) catch { _ => None }) is None)
  assert_true(
    (Some(theory(["a"], [{ lhs: ["a"], rhs: "a", }])) catch { _ => None })
    is None,
  )
  assert_true(
    (Some(theory(["a"], [{ lhs: ["b"], rhs: "a", }])) catch { _ => None })
    is None,
  )
  assert_true(
    (Some(theory(["a"], [{ lhs: [], rhs: "b", }])) catch { _ => None }) is None,
  )
  assert_true(
    (Some(
      theory(["a", "b", "c"], [
        { lhs: ["a", "b"], rhs: "c", },
        { lhs: ["b", "a"], rhs: "c", },
      ]),
    ) catch {
      _ => None
    })
    is None,
  )
}

///|
test "proof verification rejects altered steps, seeds, and claimed results" {
  let compiled = order_theory()
  let result = compiled.closure(["line", "order"])
  assert_false(
    compiled.verify_trace({
      ..result,
      steps: [result.steps[1], result.steps[2]],
    }),
  )
  assert_false(
    compiled.verify_trace({
      ..result,
      steps: [{ rule_index: -1, derived: "currency", }],
    }),
  )
  assert_false(
    compiled.verify_trace({
      ..result,
      steps: [{ ..result.steps[0], derived: "warehouse", }],
    }),
  )
  assert_false(compiled.verify_trace({ ..result, seeds: ["line"], }))
  assert_false(
    compiled.verify_trace({
      ..result,
      attributes: ["currency", "line", "name", "name", "product"],
    }),
  )
  assert_false(
    compiled.verify_entailment(result.seeds, "name", [
      result.steps[2],
      result.steps[1],
    ]),
  )
  assert_true(
    (Some(compiled.explain({ ..result, steps: [], }, "name")) catch {
      _ => None
    })
    is None,
  )
}

///|
// Fixed-point scan over strings, independent of the agenda and compiled index.
fn reference_closure(
  seeds : Array[String],
  rules : Array[Rule],
) -> Array[String] {
  let known = seeds.copy()
  for changed = true; changed; {
    let before = known.length()
    for rule in rules {
      if !known.contains(rule.rhs) && rule.lhs.all(col => known.contains(col)) {
        known.push(rule.rhs)
      }
    }
    continue known.length() != before
  }
  known.sort_by((a, b) => a.lexical_compare(b))
  known
}

///|
test "seeded differential closure and certificates across every seed subset" {
  let columns = ["a", "b", "c", "d", "e"]
  let mut state = 20261125U
  fn includes() -> Bool {
    state = state * 1664525U + 1013904223U
    (state >> 24) % 13U == 0U
  }
  for _ in 0..<100 {
    let rules : Array[Rule] = []
    let sets = Array::makei(1 << columns.length(), mask => {
      columns
      .mapi((i, col) => (i, col))
      .filter(pair => (mask & (1 << pair.0)) != 0)
      .map(pair => pair.1)
    })
    for lhs in sets {
      for rhs in columns {
        if !lhs.contains(rhs) && includes() {
          rules.push({ lhs, rhs, })
        }
      }
    }
    let compiled = theory(columns, rules)
    for seeds in sets {
      let result = compiled.closure(seeds)
      let expected = reference_closure(seeds, rules)
      assert_eq(result.attributes, expected)
      assert_eq(result.status, @budget.CompleteInDomain)
      assert_true(compiled.verify_trace(result))
      for rhs in columns {
        match compiled.implies(seeds, rhs).outcome {
          Entailed(proof) => {
            assert_true(expected.contains(rhs))
            assert_true(compiled.verify_entailment(seeds, rhs, proof))
          }
          Refuted(agreement) => {
            assert_false(expected.contains(rhs))
            assert_true(compiled.verify_counterexample(seeds, rhs, agreement))
          }
          Undetermined => fail("unexpected incomplete implication")
        }
      }
    }
  }
}
