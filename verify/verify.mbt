///|
#derive(Eq, @debug.Debug)
pub(all) struct Pair {
  first : String
  second : String
}

///|
#derive(Eq, @debug.Debug)
pub(all) struct Verdict {
  holds : Bool
  counterexample : Pair?
}

///|
/// Direct row-pair reference implementation; no partition/search helpers.
pub fn fd(
  t : @model.Table,
  lhs : Array[String],
  rhs : String,
) -> Verdict raise @model.InputError {
  let x = t.positions(lhs)
  let a = t.position(rhs)
  if x.contains(a) {
    raise @model.Invalid("trivial FD is outside the contract")
  }
  let rows = t.rows()
  for i in 0..<rows.length() {
    for j in (i + 1)..<rows.length() {
      if x.all(c => rows[i].cells[c] == rows[j].cells[c]) &&
        rows[i].cells[a] != rows[j].cells[a] {
        return {
          holds: false,
          counterexample: Some({ first: rows[i].id, second: rows[j].id, }),
        }
      }
    }
  }
  { holds: true, counterexample: None, }
}

///|
pub fn unique(
  t : @model.Table,
  columns : Array[String],
) -> Verdict raise @model.InputError {
  let x = t.positions(columns)
  let rows = t.rows()
  for i in 0..<rows.length() {
    for j in (i + 1)..<rows.length() {
      if x.all(c => rows[i].cells[c] == rows[j].cells[c]) {
        return {
          holds: false,
          counterexample: Some({ first: rows[i].id, second: rows[j].id, }),
        }
      }
    }
  }
  { holds: true, counterexample: None, }
}

///|
#derive(Eq, @debug.Debug)
pub(all) struct InclusionVerdict {
  holds : Bool
  source_distinct : Int32
  target_distinct : Int32
  target_unique : Bool
  orphan_count : Int32
  orphans : Array[String?]
  orphans_omitted : Int32
}

///|
/// Array-set reference deliberately avoids the production dictionary/set index.
pub fn inclusion(
  source : @model.Table,
  source_column : String,
  target : @model.Table,
  target_column : String,
  orphan_limit~ : Int32 = 10,
) -> InclusionVerdict raise @model.InputError {
  if source.policy != target.policy {
    raise @model.Invalid("NULL policies differ")
  }
  if orphan_limit < 0 {
    raise @model.Invalid("negative orphan limit")
  }
  let s = source.position(source_column)
  let t = target.position(target_column)
  let sv : Array[String?] = []
  let tv : Array[String?] = []
  for row in source.rows() {
    if !sv.contains(row.cells[s]) {
      sv.push(row.cells[s])
    }
  }
  for row in target.rows() {
    if !tv.contains(row.cells[t]) {
      tv.push(row.cells[t])
    }
  }
  let missing = sv.filter(v => !tv.contains(v))
  let orphans = []
  for v in missing {
    if orphans.length() < orphan_limit {
      orphans.push(v)
    }
  }
  {
    holds: missing.is_empty(),
    source_distinct: sv.length(),
    target_distinct: tv.length(),
    target_unique: tv.length() == target.row_count(),
    orphan_count: missing.length(),
    orphans,
    orphans_omitted: missing.length() - orphans.length(),
  }
}

///|
/// Recheck a supplied pair, not merely some counterexample for the same rule.
pub fn check_pair(
  t : @model.Table,
  columns : Array[String],
  pair : Pair,
  rhs~ : String? = None,
) -> Bool raise @model.InputError {
  let x = t.positions(columns)
  let a = match rhs {
    Some(id) => Some(t.position(id))
    None => None
  }
  let rows = t.rows()
  let mut first : @model.Row? = None
  let mut second : @model.Row? = None
  for row in rows {
    if row.id == pair.first {
      first = Some(row)
    }
    if row.id == pair.second {
      second = Some(row)
    }
  }
  match (first, second) {
    (Some(l), Some(r)) =>
      l.id != r.id &&
      x.all(c => l.cells[c] == r.cells[c]) &&
      (match a {
        Some(c) => l.cells[c] != r.cells[c]
        None => true
      })
    _ => false
  }
}

///|
#deprecated
pub extend Pair with Eq::{equal, not_equal}

///|
#deprecated
pub extend Pair with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Verdict with Eq::{equal, not_equal}

///|
#deprecated
pub extend Verdict with @debug.Debug::{to_repr}

///|
#deprecated
pub extend InclusionVerdict with Eq::{equal, not_equal}

///|
#deprecated
pub extend InclusionVerdict with @debug.Debug::{to_repr}
