///|
#derive(Eq, @debug.Debug)
pub(all) struct Ind {
  source_table : String
  source_column : String
  target_table : String
  target_column : String
  source_distinct : Int32
  target_distinct : Int32
  target_unique : Bool
}

///|
#derive(Eq, @debug.Debug)
pub(all) struct Report {
  status : @budget.Status
  limits : @budget.Limits
  usage : @budget.Usage
  relations : Array[Ind]
}

///|
priv struct Domain {
  table_id : String
  column_id : String
  values : Map[String?, Bool]
  value_order : Array[String?]
  unique : Bool
}

///|
/// Directed unary inclusion only, between distinct tables. Failed pairs are not retained.
pub fn discover(
  tables : Array[@model.Table],
  limits~ : @budget.Limits = @budget.defaults(),
) -> Report raise {
  let meter = @budget.meter(limits)
  let ordered = tables.copy()
  ordered.sort_by((a, b) => a.id.compare(b.id))
  let seen : Map[String, Bool] = Map([])
  for t in ordered {
    if seen.contains(t.id) {
      raise @model.Invalid("duplicate table ID")
    }
    seen[t.id] = true
    if !ordered.is_empty() && t.policy != ordered[0].policy {
      raise @model.Invalid("NULL policies differ")
    }
  }
  let relations = []
  let status = try {
    let domains : Array[Domain] = []
    for t in ordered {
      meter.charge(
        t.row_count().to_int64() * (t.column_count().to_int64() + 1L),
      )
      let rows = t.rows()
      for c, column in t.columns() {
        let values : Map[String?, Bool] = Map([])
        let value_order = []
        for row in rows {
          meter.charge(1L)
          if !values.contains(row.cells[c]) {
            value_order.push(row.cells[c])
          }
          values[row.cells[c]] = true
        }
        domains.push({
          table_id: t.id,
          column_id: column.id,
          values,
          value_order,
          unique: values.length() == rows.length(),
        })
      }
    }
    for source in domains {
      for target in domains {
        meter.charge(1L)
        if source.table_id == target.table_id {
          continue
        }
        meter.candidate()
        if source.values.length() > target.values.length() {
          continue
        }
        let mut holds = true
        for value in source.value_order {
          meter.charge(1L)
          if !target.values.contains(value) {
            holds = false
            break
          }
        }
        if holds {
          meter.result()
          relations.push({
            source_table: source.table_id,
            source_column: source.column_id,
            target_table: target.table_id,
            target_column: target.column_id,
            source_distinct: source.values.length(),
            target_distinct: target.values.length(),
            target_unique: target.unique,
          })
        }
      }
    }
    @budget.CompleteInDomain
  } catch {
    @budget.Exhausted(reason) => @budget.Partial(reason)
  }
  { status, limits, usage: meter.usage(), relations, }
}

///|
#deprecated
pub extend Ind with Eq::{equal, not_equal}

///|
#deprecated
pub extend Ind with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Report with Eq::{equal, not_equal}

///|
#deprecated
pub extend Report with @debug.Debug::{to_repr}
