///|
pub(all) enum Rule {
  Functional(Array[String], String)
  Unique(Array[String])
}

///|
pub(all) enum Outcome {
  HeldMinimal
  HeldNonminimal(Array[String])
  Violated(@verify.Pair)
  MissingColumns(Array[String])
}

///|
pub(all) struct Check {
  rule : Rule
  outcome : Outcome
}

///|
pub(all) struct Report {
  table_id : String
  baseline_status : @budget.Status
  baseline_fd_complete : Bool
  baseline_ucc_complete : Bool
  status : @budget.Status
  limits : @budget.Limits
  usage : @budget.Usage
  baseline_rules : Int64
  checked_rules : Int32
  checks : Array[Check]
}

///|
/// Direct raw-cell scan; deliberately independent of the partition index.
fn counterexample(
  rows : Array[@model.Row],
  positions : Array[Int32],
  rhs : Int32?,
  meter : @budget.Meter,
) -> @verify.Pair? raise @budget.Exhausted {
  for i in 0..<rows.length() {
    for j in (i + 1)..<rows.length() {
      meter.charge(1L)
      let mut same = true
      for p in positions {
        meter.charge(1L)
        if rows[i].cells[p] != rows[j].cells[p] {
          same = false
          break
        }
      }
      if !same {
        continue
      }
      let failure = match rhs {
        None => true
        Some(p) => {
          meter.charge(1L)
          rows[i].cells[p] != rows[j].cells[p]
        }
      }
      if failure {
        return Some({ first: rows[i].id, second: rows[j].id, })
      }
    }
  }
  None
}

///|
fn check_shape(
  columns : Array[String],
  rhs : String?,
) -> Unit raise @model.InputError {
  let seen = Map([])
  for column in columns {
    if column.is_empty() || seen.contains(column) {
      raise @model.Invalid("empty or repeated baseline column ID")
    }
    seen[column] = true
  }
  if rhs is Some(a) && (a.is_empty() || seen.contains(a)) {
    raise @model.Invalid("baseline FD must have a nontrivial singleton RHS")
  }
}

///|
fn replay_rule(
  table : @model.Table,
  rows : Array[@model.Row],
  columns : Array[String],
  rhs : String?,
  meter : @budget.Meter,
) -> Outcome raise {
  meter.charge(columns.length().to_int64() + 1L)
  check_shape(columns, rhs)
  let available = table.columns().map(c => c.id)
  let missing = columns.filter(c => !available.contains(c))
  if rhs is Some(a) && !available.contains(a) {
    missing.push(a)
  }
  if !missing.is_empty() {
    return MissingColumns(missing)
  }
  let positions = table.positions(columns)
  let rhs_position = match rhs {
    Some(a) => Some(table.position(a))
    None => None
  }
  match counterexample(rows, positions, rhs_position, meter) {
    Some(pair) => return Violated(pair)
    None => ()
  }
  for removed in columns {
    meter.charge(1L)
    let parent = columns.filter(c => c != removed)
    if counterexample(rows, table.positions(parent), rhs_position, meter)
      is None {
      return HeldNonminimal(parent)
    }
  }
  HeldMinimal
}

///|
/// Re-evaluate baseline declarations on a new snapshot, with fresh witnesses.
/// Baseline certificates are not reused and novel rules are not discovered.
pub fn compare(
  table : @model.Table,
  baseline : @engine.Discovery,
  limits~ : @budget.Limits = @budget.defaults(),
) -> Report raise {
  if table.id != baseline.table_id {
    raise @model.Invalid("baseline table ID differs")
  }
  if table.policy != baseline.null_policy {
    raise @model.Invalid("cannot compare different NULL policies")
  }
  let meter = @budget.meter(limits)
  let checks = []
  let status = try {
    meter.charge(
      table.row_count().to_int64() * (table.column_count().to_int64() + 1L),
    )
    let rows = table.rows()
    for f in baseline.fds {
      meter.candidate()
      let outcome = replay_rule(table, rows, f.lhs, Some(f.rhs), meter)
      meter.result()
      checks.push({ rule: Functional(f.lhs.copy(), f.rhs), outcome, })
    }
    for k in baseline.uccs {
      meter.candidate()
      let outcome = replay_rule(table, rows, k.columns, None, meter)
      meter.result()
      checks.push({ rule: Unique(k.columns.copy()), outcome, })
    }
    @budget.CompleteInDomain
  } catch {
    @budget.Exhausted(reason) => @budget.Partial(reason)
    error => raise error
  }
  {
    table_id: table.id,
    baseline_status: baseline.status,
    baseline_fd_complete: baseline.fd_complete,
    baseline_ucc_complete: baseline.ucc_complete,
    baseline_rules: baseline.fds.length().to_int64() +
    baseline.uccs.length().to_int64(),
    checked_rules: checks.length(),
    status,
    limits,
    usage: meter.usage(),
    checks,
  }
}
