///|
test "snapshot ownership and exact strings" {
  let cells = [Some("01"), Some("é")]
  let columns = [Column::{ id: "a", name: "A", }, { id: "b", name: "B", }]
  let input = [Row::{ id: "r", cells, }]
  let t = table("t", columns, input)
  cells[0] = Some("1")
  columns[0] = { id: "changed", name: "changed", }
  let exposed = t.rows()
  exposed[0].cells[0] = None
  assert_eq(t.rows()[0].cells, [Some("01"), Some("é")])
  assert_true(t.rows()[0].cells[1] != Some("é"))
}

///|
test "malformed schemas and rows are rejected" {
  let c = Column::{ id: "a", name: "same", }
  assert_true(
    try {
      ignore(table("t", [c, { id: "b", name: "same", }], []))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(table("t", [c], [{ id: "r", cells: [], }]))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(table("t", [], [{ id: "r", cells: [], }, { id: "r", cells: [], }]))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "exact row ID lookup preserves lexical order and snapshot ownership" {
  let ids = ["é", "r2", "r10", "é", "z"]
  let cols : Array[Column] = ids.map(id => { id, name: id, })
  let t = table(
    "t",
    cols,
    ids.map(id => { id, cells: ids.map(c => Some(c + ":" + id)), }),
  )
  for row in t.rows() {
    assert_eq(t.row(row.id), Some(row))
    for i, col in t.columns() {
      assert_eq(t.position(col.id), i)
      assert_eq(row.cells[i], Some(col.id + ":" + row.id))
    }
  }
  let copy = t.row("r10").unwrap()
  copy.cells[0] = None
  assert_true(t.row("r10").unwrap().cells[0] is Some(_))
  assert_true(t.row("r1") is None)
  assert_true(t.row("zz") is None)
  assert_true(table("empty", [], []).row("r1") is None)
}
