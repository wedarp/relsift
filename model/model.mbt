///|
/// NULL is either rejected at construction or treated as one comparable value.
#derive(Eq, @debug.Debug)
pub(all) enum NullPolicy {
  RejectNull
  NullAsValue
}

///|
#derive(Eq, @debug.Debug)
pub(all) suberror InputError {
  Invalid(String)
}

///|
#derive(Eq, @debug.Debug)
pub(all) struct Column {
  id : String
  name : String
}

///|
#derive(Eq, @debug.Debug)
pub(all) struct Row {
  id : String
  cells : Array[String?]
}

///|
/// Owned snapshot. Construction sorts stable IDs and copies all mutable arrays.
#derive(@debug.Debug)
pub struct Table {
  id : String
  policy : NullPolicy
  priv columns_data : Array[Column]
  priv rows_data : Array[Row]
}

///|
pub fn table(
  id : String,
  columns : Array[Column],
  rows : Array[Row],
  policy~ : NullPolicy = RejectNull,
) -> Table raise InputError {
  if id.is_empty() {
    raise Invalid("empty table ID")
  }
  let ids : Map[String, Bool] = Map([])
  let names : Map[String, Bool] = Map([])
  for c in columns {
    if c.id.is_empty() || c.name.is_empty() {
      raise Invalid("empty column ID/name")
    }
    if ids.contains(c.id) || names.contains(c.name) {
      raise Invalid("duplicate column ID/name")
    }
    ids[c.id] = true
    names[c.name] = true
  }
  let order = Array::makei(columns.length(), i => i)
  order.sort_by((a, b) => columns[a].id.lexical_compare(columns[b].id))
  let ordered_columns = order.map(i => columns[i])
  let row_ids : Map[String, Bool] = Map([])
  let copied : Array[Row] = []
  for row in rows {
    if row.id.is_empty() || row_ids.contains(row.id) {
      raise Invalid("empty or duplicate row ID")
    }
    row_ids[row.id] = true
    if row.cells.length() != columns.length() {
      raise Invalid("row width mismatch")
    }
    if policy == RejectNull && row.cells.any(v => v is None) {
      raise Invalid("NULL rejected by policy")
    }
    copied.push({ id: row.id, cells: order.map(i => row.cells[i]), })
  }
  copied.sort_by((a, b) => a.id.lexical_compare(b.id))
  { id, policy, columns_data: ordered_columns, rows_data: copied, }
}

///|
pub fn Table::columns(self : Table) -> Array[Column] {
  self.columns_data.copy()
}

///|
pub fn Table::rows(self : Table) -> Array[Row] {
  self.rows_data.map(r => { id: r.id, cells: r.cells.copy(), })
}

///|
pub fn Table::row_count(self : Table) -> Int32 {
  self.rows_data.length()
}

///|
pub fn Table::column_count(self : Table) -> Int32 {
  self.columns_data.length()
}

///|
pub fn Table::position(self : Table, id : String) -> Int32 raise InputError {
  for i, c in self.columns_data {
    if c.id == id {
      return i
    }
  }
  raise Invalid("unknown column ID: " + id)
}

///|
pub fn Table::positions(
  self : Table,
  ids : Array[String],
) -> Array[Int32] raise InputError {
  let result = self.ordered_positions(ids)
  result.sort()
  result
}

///|
/// Resolve a column mapping in caller order, rejecting duplicate IDs.
pub fn Table::ordered_positions(
  self : Table,
  ids : Array[String],
) -> Array[Int32] raise InputError {
  let result = []
  let seen : Map[Int32, Bool] = Map([])
  for id in ids {
    let index = self.position(id)
    if seen.contains(index) {
      raise Invalid("repeated column ID")
    }
    seen[index] = true
    result.push(index)
  }
  result
}

///|
#deprecated
pub extend NullPolicy with Eq::{equal, not_equal}

///|
#deprecated
pub extend NullPolicy with @debug.Debug::{to_repr}

///|
#deprecated
pub extend InputError with Eq::{equal, not_equal}

///|
#deprecated
pub extend InputError with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Column with Eq::{equal, not_equal}

///|
#deprecated
pub extend Column with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Row with Eq::{equal, not_equal}

///|
#deprecated
pub extend Row with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Table with @debug.Debug::{to_repr}
