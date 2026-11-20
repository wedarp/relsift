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
