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
/// Compare raw tuples without using the discovery partition index.
fn counterexample(
  rows : Array[@model.Row],
  positions : Array[Int32],
  rhs : Int32?,
  meter : @budget.Meter,
) -> @verify.Pair? raise @budget.Exhausted {
  let first_rows : Map[Array[String?], Int32] = Map([])
  let mut best : (Int32, Int32)? = None
  for j, row in rows {
    meter.charge(positions.length().to_int64() + 1L)
    let key = positions.map(p => row.cells[p])
    match first_rows.get(key) {
      None => first_rows[key] = j
      Some(i) => {
        // The first differing row in a group always differs from its first row.
        let improves = match best {
          Some((previous, _)) => i < previous
          None => true
        }
        if !improves {
          continue
        }
        meter.charge(1L)
        if rhs is Some(p) && rows[i].cells[p] == row.cells[p] {
          continue
        }
        if i == 0 {
          return Some({ first: rows[i].id, second: row.id, })
        }
        best = Some((i, j))
      }
    }
  }
  best.map(fn(pair) {
    let (i, j) = pair
    { first: rows[i].id, second: rows[j].id, }
  })
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
/// Validate declarations before spending the budget on the new snapshot.
fn validate_rules(baseline : @engine.Discovery) -> Unit raise @model.InputError {
  let fds : Map[(Array[String], String), Bool] = Map([])
  for i, f in baseline.fds {
    check_shape(f.lhs, Some(f.rhs))
    if f.lhs.length() > baseline.limits.max_lhs ||
      f.lhs.length() >= baseline.column_count {
      raise @model.Invalid(
        "baseline FD \{i}: width outside the discovery domain",
      )
    }
    let lhs = f.lhs.copy()
    lhs.sort()
    let key = (lhs, f.rhs)
    if fds.contains(key) {
      raise @model.Invalid("baseline FD \{i}: duplicate dependency")
    }
    fds[key] = true
  }
  let uccs : Map[Array[String], Bool] = Map([])
  for i, k in baseline.uccs {
    check_shape(k.columns, None)
    if k.columns.length() > baseline.limits.max_ucc_width ||
      k.columns.length() > baseline.column_count {
      raise @model.Invalid(
        "baseline UCC \{i}: width outside the discovery domain",
      )
    }
    let columns = k.columns.copy()
    columns.sort()
    if uccs.contains(columns) {
      raise @model.Invalid("baseline UCC \{i}: duplicate unique combination")
    }
    uccs[columns] = true
  }
}

///|
fn replay_rule(
  available : Map[String, Int32],
  rows : Array[@model.Row],
  columns : Array[String],
  rhs : String?,
  meter : @budget.Meter,
) -> Outcome raise {
  meter.charge(columns.length().to_int64() + 1L)
  let missing = columns.filter(c => !available.contains(c))
  if rhs is Some(a) && !available.contains(a) {
    missing.push(a)
  }
  if !missing.is_empty() {
    return MissingColumns(missing)
  }
  let positions = columns.map(c => available[c])
  let rhs_position = match rhs {
    Some(a) => Some(available[a])
    None => None
  }
  match counterexample(rows, positions, rhs_position, meter) {
    Some(pair) => return Violated(pair)
    None => ()
  }
  for removed in 0..<columns.length() {
    meter.charge(columns.length().to_int64() + 1L)
    let parent = Array::makei(positions.length() - 1, i => {
      positions[if i < removed { i } else { i + 1 }]
    })
    if counterexample(rows, parent, rhs_position, meter) is None {
      return HeldNonminimal(columns.filter(c => c != columns[removed]))
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
  validate_rules(baseline)
  let checks = []
  let status = try {
    meter.charge(
      (table.row_count().to_int64() + 1L) *
      (table.column_count().to_int64() + 1L),
    )
    let rows = table.rows()
    let available : Map[String, Int32] = Map([])
    for i, c in table.columns() {
      available[c.id] = i
    }
    for f in baseline.fds {
      meter.candidate()
      let outcome = replay_rule(available, rows, f.lhs, Some(f.rhs), meter)
      meter.result()
      checks.push({ rule: Functional(f.lhs.copy(), f.rhs), outcome, })
    }
    for k in baseline.uccs {
      meter.candidate()
      let outcome = replay_rule(available, rows, k.columns, None, meter)
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
