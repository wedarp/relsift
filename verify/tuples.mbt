///|
/// One sampled orphan tuple with its first source row and scanned multiplicity.
pub(all) struct TupleOrphan {
  values : Array[String?]
  first_source_row : String
  source_count : Int32
}

///|
pub(all) struct TupleInclusion {
  source_table : String
  target_table : String
  source_columns : Array[String]
  target_columns : Array[String]
  status : @budget.Status
  holds : Bool?
  target_unique : Bool?
  source_rows_checked : Int32
  source_distinct : Int32
  target_distinct : Int32?
  orphan_tuples : Int32
  orphan_rows : Int32
  orphans : Array[TupleOrphan]
  usage : @budget.Usage
}

///|
/// Verify an explicit, ordered tuple mapping. Tuple equality uses raw cells.
pub fn tuple_inclusion(
  source : @model.Table,
  source_columns : Array[String],
  target : @model.Table,
  target_columns : Array[String],
  orphan_limit~ : Int32 = 10,
  limits~ : @budget.Limits = @budget.defaults(),
) -> TupleInclusion raise {
  if source.policy != target.policy {
    raise @model.Invalid("NULL policies differ")
  }
  if source_columns.is_empty() ||
    source_columns.length() != target_columns.length() {
    raise @model.Invalid("tuple mapping requires equal nonzero column counts")
  }
  if orphan_limit < 0 {
    raise @model.Invalid("negative orphan limit")
  }
  let from = source.ordered_positions(source_columns)
  let to = target.ordered_positions(target_columns)
  let meter = @budget.meter(limits)
  let target_values : Map[Array[String?], Bool] = Map([])
  // None marks a seen source tuple outside the sample or already in the target.
  let source_values : Map[Array[String?], Int32?] = Map([])
  let orphans : Array[TupleOrphan] = []
  let mut target_distinct : Int32? = None
  let mut target_unique : Bool? = None
  let mut holds : Bool? = None
  let mut source_rows_checked = 0
  let mut orphan_tuples = 0
  let mut orphan_rows = 0
  let status = try {
    meter.candidate()
    meter.charge(
      target.row_count().to_int64() * (target.column_count().to_int64() + 1L),
    )
    for row in target.rows() {
      meter.charge(to.length().to_int64() + 1L)
      target_values[to.map(p => row.cells[p])] = true
    }
    target_distinct = Some(target_values.length())
    target_unique = Some(target_values.length() == target.row_count())
    meter.charge(
      source.row_count().to_int64() * (source.column_count().to_int64() + 1L),
    )
    for row in source.rows() {
      meter.charge(from.length().to_int64() + 1L)
      let values = from.map(p => row.cells[p])
      let orphan = !target_values.contains(values)
      if orphan {
        holds = Some(false)
      }
      match source_values.get(values) {
        Some(Some(i)) => {
          let recorded = orphans[i]
          orphans[i] = { ..recorded, source_count: recorded.source_count + 1, }
        }
        Some(None) => ()
        None => {
          let sample = if orphan && orphans.length() < orphan_limit {
            meter.result()
            let i = orphans.length()
            orphans.push({ values, first_source_row: row.id, source_count: 1, })
            Some(i)
          } else {
            None
          }
          source_values[values] = sample
          if orphan {
            orphan_tuples += 1
          }
        }
      }
      source_rows_checked += 1
      if orphan {
        orphan_rows += 1
      }
    }
    if holds is None {
      holds = Some(true)
    }
    @budget.CompleteInDomain
  } catch {
    @budget.Exhausted(reason) => @budget.Partial(reason)
  }
  {
    source_table: source.id,
    target_table: target.id,
    source_columns: source_columns.copy(),
    target_columns: target_columns.copy(),
    status,
    holds,
    target_unique,
    source_rows_checked,
    source_distinct: source_values.length(),
    target_distinct,
    orphan_tuples,
    orphan_rows,
    orphans,
    usage: meter.usage(),
  }
}
