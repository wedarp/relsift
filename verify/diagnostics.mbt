///|
#derive(Eq, @debug.Debug)
pub(all) struct ConflictGroup {
  determinant : Array[String?]
  rows : Array[String]
  distinct_rhs : Int32
  violating_pairs : Int64
  witness : Pair
}

///|
#derive(Eq, @debug.Debug)
pub(all) struct FdDiagnosis {
  lhs : Array[String]
  rhs : String
  status : @budget.Status
  holds : Bool?
  conflicting_groups : Int32
  violating_pairs : Int64
  groups : Array[ConflictGroup]
  usage : @budget.Usage
}

///|
#derive(Eq, @debug.Debug)
pub(all) struct CollisionGroup {
  values : Array[String?]
  rows : Array[String]
  collision_pairs : Int64
}

///|
#derive(Eq, @debug.Debug)
pub(all) struct UniqueDiagnosis {
  columns : Array[String]
  status : @budget.Status
  holds : Bool?
  collision_groups : Int32
  excess_rows : Int32
  collision_pairs : Int64
  groups : Array[CollisionGroup]
  usage : @budget.Usage
}

///|
#derive(Eq, @debug.Debug)
pub(all) struct OrphanGroup {
  value : String?
  source_rows : Array[String]
}

///|
#derive(Eq, @debug.Debug)
pub(all) struct InclusionDiagnosis {
  status : @budget.Status
  holds : Bool?
  target_unique : Bool?
  orphan_values : Int32
  orphan_rows : Int32
  groups : Array[OrphanGroup]
  usage : @budget.Usage
}

///|
priv struct RowGroup {
  values : Array[String?]
  members : Array[Int32]
}

///|
fn grouped_rows(
  rows : Array[@model.Row],
  columns : Array[Int32],
  meter : @budget.Meter,
) -> Array[RowGroup] raise @budget.Exhausted {
  let lookup : Map[Array[String?], Int32] = Map([])
  let groups : Array[RowGroup] = []
  for i, row in rows {
    meter.charge(columns.length().to_int64() + 1L)
    let values = columns.map(c => row.cells[c])
    match lookup.get(values) {
      Some(index) => groups[index].members.push(i)
      None => {
        lookup[values] = groups.length()
        groups.push({ values, members: [i], })
      }
    }
  }
  groups
}

///|
fn pair_count(size : Int32) -> Int64 {
  size.to_int64() * (size.to_int64() - 1L) / 2L
}

///|
/// Complete counts are promised only for CompleteInDomain; partial counts are lower bounds.
pub fn diagnose_fd(
  t : @model.Table,
  lhs : Array[String],
  rhs : String,
  limits~ : @budget.Limits = @budget.defaults(),
) -> FdDiagnosis raise {
  let positions = t.positions(lhs)
  let rhs_position = t.position(rhs)
  if positions.contains(rhs_position) {
    raise @model.Invalid("trivial FD is outside the contract")
  }
  let names = positions.map(c => t.columns()[c].id)
  let meter = @budget.meter(limits)
  let groups = []
  let mut conflicting_groups = 0
  let mut violating_pairs = 0L
  let mut holds : Bool? = None
  let status = try {
    meter.candidate()
    meter.charge(t.row_count().to_int64() + 1L)
    let rows = t.rows()
    for group in grouped_rows(rows, positions, meter) {
      let counts : Map[String?, Int32] = Map([])
      let mut witness : Pair? = None
      let first = group.members[0]
      for index in group.members {
        meter.charge(1L)
        let value = rows[index].cells[rhs_position]
        counts[value] = counts.get(value).unwrap_or(0) + 1
        if witness is None && value != rows[first].cells[rhs_position] {
          witness = Some({ first: rows[first].id, second: rows[index].id, })
        }
      }
      if counts.length() <= 1 {
        continue
      }
      holds = Some(false)
      conflicting_groups += 1
      let mut pairs = pair_count(group.members.length())
      for _, count in counts {
        meter.charge(1L)
        pairs -= pair_count(count)
      }
      violating_pairs += pairs
      meter.result()
      groups.push({
        determinant: group.values,
        rows: group.members.map(i => rows[i].id),
        distinct_rhs: counts.length(),
        violating_pairs: pairs,
        witness: witness.unwrap(),
      })
    }
    if holds is None {
      holds = Some(true)
    }
    @budget.CompleteInDomain
  } catch {
    @budget.Exhausted(reason) => @budget.Partial(reason)
  }
  {
    lhs: names,
    rhs,
    status,
    holds,
    conflicting_groups,
    violating_pairs,
    groups,
    usage: meter.usage(),
  }
}

///|
pub fn diagnose_unique(
  t : @model.Table,
  columns : Array[String],
  limits~ : @budget.Limits = @budget.defaults(),
) -> UniqueDiagnosis raise {
  let positions = t.positions(columns)
  let names = positions.map(c => t.columns()[c].id)
  let meter = @budget.meter(limits)
  let groups = []
  let mut collision_groups = 0
  let mut excess_rows = 0
  let mut collision_pairs = 0L
  let mut holds : Bool? = None
  let status = try {
    meter.candidate()
    meter.charge(t.row_count().to_int64() + 1L)
    let rows = t.rows()
    for group in grouped_rows(rows, positions, meter) {
      meter.charge(1L)
      if group.members.length() <= 1 {
        continue
      }
      holds = Some(false)
      collision_groups += 1
      excess_rows += group.members.length() - 1
      let pairs = pair_count(group.members.length())
      collision_pairs += pairs
      meter.result()
      groups.push({
        values: group.values,
        rows: group.members.map(i => rows[i].id),
        collision_pairs: pairs,
      })
    }
    if holds is None {
      holds = Some(true)
    }
    @budget.CompleteInDomain
  } catch {
    @budget.Exhausted(reason) => @budget.Partial(reason)
  }
  {
    columns: names,
    status,
    holds,
    collision_groups,
    excess_rows,
    collision_pairs,
    groups,
    usage: meter.usage(),
  }
}

///|
pub fn diagnose_inclusion(
  source : @model.Table,
  source_column : String,
  target : @model.Table,
  target_column : String,
  limits~ : @budget.Limits = @budget.defaults(),
) -> InclusionDiagnosis raise {
  if source.policy != target.policy {
    raise @model.Invalid("NULL policies differ")
  }
  let s = source.position(source_column)
  let t = target.position(target_column)
  let meter = @budget.meter(limits)
  let groups = []
  let mut orphan_values = 0
  let mut orphan_rows = 0
  let mut holds : Bool? = None
  let mut target_unique : Bool? = None
  let status = try {
    meter.candidate()
    meter.charge(
      source.row_count().to_int64() + target.row_count().to_int64() + 1L,
    )
    let target_values : Map[String?, Bool] = Map([])
    for row in target.rows() {
      meter.charge(1L)
      target_values[row.cells[t]] = true
    }
    target_unique = Some(target_values.length() == target.row_count())
    let source_rows = source.rows()
    for group in grouped_rows(source_rows, [s], meter) {
      meter.charge(1L)
      if target_values.contains(group.values[0]) {
        continue
      }
      holds = Some(false)
      orphan_values += 1
      orphan_rows += group.members.length()
      meter.result()
      groups.push({
        value: group.values[0],
        source_rows: group.members.map(i => source_rows[i].id),
      })
    }
    if holds is None {
      holds = Some(true)
    }
    @budget.CompleteInDomain
  } catch {
    @budget.Exhausted(reason) => @budget.Partial(reason)
  }
  {
    status,
    holds,
    target_unique,
    orphan_values,
    orphan_rows,
    groups,
    usage: meter.usage(),
  }
}

///|
#deprecated
pub extend ConflictGroup with Eq::{equal, not_equal}

///|
#deprecated
pub extend ConflictGroup with @debug.Debug::{to_repr}

///|
#deprecated
pub extend FdDiagnosis with Eq::{equal, not_equal}

///|
#deprecated
pub extend FdDiagnosis with @debug.Debug::{to_repr}

///|
#deprecated
pub extend CollisionGroup with Eq::{equal, not_equal}

///|
#deprecated
pub extend CollisionGroup with @debug.Debug::{to_repr}

///|
#deprecated
pub extend UniqueDiagnosis with Eq::{equal, not_equal}

///|
#deprecated
pub extend UniqueDiagnosis with @debug.Debug::{to_repr}

///|
#deprecated
pub extend OrphanGroup with Eq::{equal, not_equal}

///|
#deprecated
pub extend OrphanGroup with @debug.Debug::{to_repr}

///|
#deprecated
pub extend InclusionDiagnosis with Eq::{equal, not_equal}

///|
#deprecated
pub extend InclusionDiagnosis with @debug.Debug::{to_repr}
