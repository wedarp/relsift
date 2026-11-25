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
  null_policy : @model.NullPolicy?
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
  let ordered = ordered_tables(tables)
  let relations = []
  let status = try {
    let domains : Array[Domain] = []
    for t in ordered {
      meter.charge(
        (t.row_count().to_int64() + 1L) * (t.column_count().to_int64() + 1L),
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
  {
    null_policy: if ordered.is_empty() {
      None
    } else {
      Some(ordered[0].policy)
    },
    status,
    limits,
    usage: meter.usage(),
    relations,
  }
}

///|
fn ordered_tables(
  tables : Array[@model.Table],
) -> Array[@model.Table] raise @model.InputError {
  let ordered = tables.copy()
  ordered.sort_by((a, b) => a.id.lexical_compare(b.id))
  for i, t in ordered {
    if i > 0 && t.id == ordered[i - 1].id {
      raise @model.Invalid("duplicate table ID")
    }
    if t.policy != ordered[0].policy {
      raise @model.Invalid("NULL policies differ")
    }
  }
  ordered
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
