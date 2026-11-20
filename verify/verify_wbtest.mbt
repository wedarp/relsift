///|
fn orders(duplicate~ : Bool = false) -> @model.Table raise {
  let cells = [
    ["O1", "1", "P1", "Pen"],
    ["O1", "2", "P2", "Book"],
    ["O2", "1", "P2", "Book"],
    ["O2", "2", "P1", "Pen"],
  ]
  let rows = cells.mapi((i, r) => @model.Row::{
    id: "r\{i + 1}",
    cells: r.map(v => Some(v)),
  })
  if duplicate {
    rows.push({ id: "r5", cells: cells[0].map(v => Some(v)), })
  }
  @model.table(
    "orders",
    ["O", "L", "P", "N"].map(id => { id, name: id, }),
    rows,
  )
}

///|
/// Independent exhaustive subset enumeration for the initial hand-computable case.
test "all minimal FDs and UCCs including duplicate multiplicity" {
  for duplicate in [false, true] {
    let t = orders(duplicate~)
    let cols = ["O", "L", "P", "N"]
    let fds : Array[String] = []
    let keys : Array[String] = []
    for mask in 0..<16 {
      let x = []
      for i, c in cols {
        if (mask & (1 << i)) != 0 {
          x.push(c)
        }
      }
      if unique(t, x).holds &&
        x.all(c => !unique(t, x.filter(v => v != c)).holds) {
        keys.push(x.join(""))
      }
      for a in cols {
        if !x.contains(a) &&
          fd(t, x, a).holds &&
          x.all(c => !fd(t, x.filter(v => v != c), a).holds) {
          fds.push(x.join("") + "->" + a)
        }
      }
    }
    fds.sort()
    let expected = [
      "LP->O", "LN->O", "OP->L", "ON->L", "N->P", "OL->P", "P->N", "OL->N",
    ]
    expected.sort()
    assert_eq(fds, expected)
    keys.sort()
    assert_eq(keys, if duplicate { [] } else { ["LN", "LP", "OL", "ON", "OP"] })
  }
}

///|
test "NULL, empty strings, degenerate inputs and independent witnesses" {
  let columns = [@model.Column::{ id: "c", name: "c", }]
  let empty = @model.table("empty", columns, [])
  assert_true(fd(empty, [], "c").holds)
  assert_true(unique(empty, []).holds)
  let t = @model.table(
    "t",
    columns,
    [{ id: "1", cells: [None], }, { id: "2", cells: [Some("")], }],
    policy=@model.NullAsValue,
  )
  assert_true(unique(t, ["c"]).holds)
  assert_true(!fd(t, [], "c").holds)
  assert_true(check_pair(t, [], { first: "1", second: "2", }, rhs=Some("c")))
  assert_true(!check_pair(t, [], { first: "1", second: "1", }))
  assert_true(
    try {
      ignore(@model.table("bad", columns, t.rows()))
      false
    } catch {
      _ => true
    },
  )
  let inc = inclusion(t, "c", t, "c")
  assert_true(inc.holds)
  assert_eq(inc.source_distinct, 2)
}
