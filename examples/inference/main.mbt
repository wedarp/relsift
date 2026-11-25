///|
fn main raise {
  let rules = @rules.theory(
    ["order_id", "line_no", "product_id", "product_name", "warehouse"],
    [
      { lhs: ["order_id", "line_no"], rhs: "product_id", },
      { lhs: ["product_id"], rhs: "product_name", },
    ],
  )
  let lhs = ["order_id", "line_no"]
  let name = rules.implies(lhs, "product_name")
  guard name.outcome is @rules.Entailed(proof) else {
    fail("expected name derivation")
  }
  assert_true(rules.verify_entailment(lhs, name.rhs, proof))
  for step in proof {
    println("premise \{step.rule_index} derives \{step.derived}")
  }
  let warehouse = rules.implies(lhs, "warehouse")
  guard warehouse.outcome is @rules.Refuted(agreement) else {
    fail("expected warehouse counterexample")
  }
  assert_true(rules.verify_counterexample(lhs, warehouse.rhs, agreement))
  println("counterexample rows agree on: " + agreement.join(", "))
}
