///|
pub fn regression(value : @regression.Report) -> Json {
  let checks : Array[Json] = value.checks.map(c => {
    let rule : Json = match c.rule {
      Functional(lhs, rhs) => { "kind": "fd", "lhs": lhs, "rhs": rhs }
      Unique(columns) => { "kind": "unique", "columns": columns }
    }
    let outcome : Json = match c.outcome {
      HeldMinimal => { "kind": "held_minimal" }
      HeldNonminimal(columns) =>
        { "kind": "held_nonminimal", "smaller_columns": columns }
      Violated(p) => { "kind": "violated", "counterexample": pair(p) }
      MissingColumns(columns) =>
        { "kind": "missing_columns", "columns": columns }
    }
    { "rule": rule, "outcome": outcome }
  })
  {
    "table_id": value.table_id,
    "baseline_status": status(value.baseline_status),
    "baseline_fd_complete": value.baseline_fd_complete,
    "baseline_ucc_complete": value.baseline_ucc_complete,
    "status": status(value.status),
    "limits": limits(value.limits),
    "usage": usage(value.usage),
    "baseline_rules": value.baseline_rules,
    "checked_rules": value.checked_rules,
    "checks": checks,
  }
}

///|
pub fn compare_report(
  tables : Array[@model.Table],
  baseline : EvidenceReport,
  limits~ : @budget.Limits = @budget.defaults(),
) -> Json raise {
  let reports = baseline.tables.map(b => {
    @regression.compare(find_table(tables, b.table_id), b, limits~)
  })
  let partial = reports.any(r => r.status is @budget.Partial(_))
  let violations = reports.any(r => {
    r.checks.any(c => {
      c.outcome is @regression.Violated(_) ||
      c.outcome is @regression.MissingColumns(_)
    })
  })
  {
    "schema_version": 1,
    "status": status(
      if partial {
        @budget.Partial("table_budget")
      } else {
        @budget.CompleteInDomain
      },
    ),
    "baseline_status": status(baseline.status),
    "baseline_authenticated": false,
    "new_rules_searched": false,
    "has_violations": violations,
    "untracked_tables": tables
    .filter(t => !baseline.tables.any(b => b.table_id == t.id))
    .map(t => t.id),
    "tables": reports.map(regression),
  }
}
