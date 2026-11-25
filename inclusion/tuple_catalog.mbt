///|
priv struct TupleProjection {
  values : Array[Array[Int32]]
  membership : Map[Array[Int32], Bool]
}

///|
priv struct TupleTable {
  id : String
  columns : Array[String]
  rows : Array[Array[Int32]]
  projections : Map[Array[Int32], TupleProjection]
}

///|
priv struct TupleSearch {
  meter : @budget.Meter
  options : TupleOptions
  relations : Array[TupleInd]
  mut cached : Int32
  mut built : Int64
  mut pruned : Int32
  mut checked : Int32
}

///|
fn TupleSearch::encode(
  self : TupleSearch,
  tables : Array[@model.Table],
) -> Array[TupleTable] raise @budget.Exhausted {
  let dictionary : Map[String?, Int32] = Map([])
  let catalog = []
  for table in tables {
    let width = table.column_count().to_int64()
    self.meter.charge(
      width + table.row_count().to_int64() * (width * 2L + 1L) + 1L,
    )
    let rows = table
      .rows()
      .map(row => {
        row.cells.map(value => {
          match dictionary.get(value) {
            Some(code) => code
            None => {
              let code = dictionary.length()
              dictionary[value] = code
              code
            }
          }
        })
      })
    catalog.push({
      id: table.id,
      columns: table.columns().map(column => column.id),
      rows,
      projections: Map([]),
    })
  }
  catalog
}

///|
/// Column positions are in canonical order. Cached keys and tuples are owned.
fn TupleSearch::projection(
  self : TupleSearch,
  table : TupleTable,
  columns : Array[Int32],
) -> TupleProjection raise @budget.Exhausted {
  let width = columns.length().to_int64()
  self.meter.charge(width + 1L)
  if table.projections.get(columns) is Some(hit) {
    self.meter.cache_hit()
    return hit
  }
  self.meter.charge(table.rows.length().to_int64() * (width + 1L))
  let membership : Map[Array[Int32], Bool] = Map([])
  let values = []
  for row in table.rows {
    let tuple = columns.map(p => row[p])
    if !membership.contains(tuple) {
      membership[tuple] = true
      values.push(tuple)
    }
  }
  let projection = { values, membership, }
  self.built += 1L
  if self.cached < self.options.max_cached_projections {
    table.projections[columns] = projection
    self.cached += 1
  }
  projection
}

///|
priv struct Containment {
  source_distinct : Int32
  target_distinct : Int32
  target_unique : Bool
}

///|
fn TupleSearch::containment(
  self : TupleSearch,
  source : TupleTable,
  target : TupleTable,
  mapping : Array[(Int32, Int32)],
) -> Containment? raise @budget.Exhausted {
  let width = mapping.length().to_int64()
  self.meter.charge(width * (width + 3L) + 1L)
  let order = Array::makei(mapping.length(), i => i)
  order.sort_by((a, b) => mapping[a].1.compare(mapping[b].1))
  let from = self.projection(source, mapping.map(p => p.0))
  let to = self.projection(target, order.map(i => mapping[i].1))
  if from.values.length() > to.values.length() {
    return None
  }
  let mut permuted = false
  for i, slot in order {
    if i != slot {
      permuted = true
      break
    }
  }
  for values in from.values {
    self.meter.charge(width + 1L)
    let aligned = if permuted { order.map(p => values[p]) } else { values }
    if !to.membership.contains(aligned) {
      return None
    }
  }
  Some({
    source_distinct: from.values.length(),
    target_distinct: to.values.length(),
    target_unique: target.rows.length() == to.values.length(),
  })
}
