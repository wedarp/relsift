///|
fn main raise {
  explain_order_line()
  audit_discovered_orders()
}

///|
fn explain_order_line() -> Unit raise {
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

///|
fn audit_discovered_orders() -> Unit raise {
  let csv =
    #|order_id,line_no,product_id,product_name
    #|O1,1,P1,Pen
    #|O1,2,P2,Book
    #|O2,1,P2,Book
    #|O2,2,P1,Pen
  let table = @codec.parse_csv(csv, "orders")
  let snapshot = @engine.discover(table)
  let columns = table.columns().map(column => column.id)
  let declared = @rules.theory(
    columns,
    snapshot.fds.map(fd => { lhs: fd.lhs, rhs: fd.rhs, }),
  )
  let cover = declared.minimal_cover()
  let reduced = @rules.theory(columns, cover.rules)
  let audit = declared.audit_cover(reduced)
  assert_true(audit.comparison.left_to_right is @rules.EntailsAll)
  assert_true(audit.comparison.right_to_left is @rules.EntailsAll)
  assert_true(audit.minimality is @rules.Irreducible)
  println(
    "observed FDs: \{snapshot.fds.length()}, equivalent cover: \{cover.rules.length()}",
  )
  let duplicate = @codec.parse_csv(csv + "\nO1,1,P1,Pen", "duplicated-orders")
  let keys = reduced.schema_keys()
  assert_eq(keys.keys.length(), 5)
  for key in keys.keys {
    assert_true(reduced.verify_schema_key(key))
    assert_true(@verify.unique(table, key.columns).holds)
    assert_false(@verify.unique(duplicate, key.columns).holds)
  }
  println(
    "logical keys: \{keys.keys.length()}, unique after duplicating a row: 0",
  )
}
