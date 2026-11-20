///|
fn main raise {
  let source =
    #|order_id,line_no,product_id,product_name
    #|O1,1,P1,Pen
    #|O1,2,P2,Book
    #|O2,1,P2,Book
    #|O2,2,P1,Pen
  let t = @codec.parse_csv(source, "orders")
  let result = @relsift.discover(t)
  assert_eq(result.fds.length(), 8)
  assert_eq(result.uccs.length(), 5)
  for f in result.fds {
    assert_true(@relsift.verify_fd(t, f))
  }
  for k in result.uccs {
    assert_true(@relsift.verify_ucc(t, k))
  }
  let failure = @verify.fd(t, ["order_id"], "product_id")
  assert_true(!failure.holds)
  println(@codec.explain(result))
  println(@codec.canonical(@codec.verdict(failure)))
  let rows = t.rows()
  rows.push({ id: "r5", cells: t.rows()[0].cells, })
  let repeated = @model.table("repeated", t.columns(), rows)
  let after = @relsift.discover(repeated)
  assert_eq(after.fds, result.fds)
  assert_true(after.uccs.is_empty())
}
