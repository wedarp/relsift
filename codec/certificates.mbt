///|
/// A parsed claim, not an authenticated record of a previous execution.
pub struct EvidenceReport {
  status : @budget.Status
  tables : Array[@engine.Discovery]
}

///|
fn natural(value : Json) -> Int32 raise {
  let n : Int32 = @json.from_json(value)
  if n < 0 || value != Json::number(n.to_double()) {
    raise @model.Invalid("expected nonnegative integer")
  }
  n
}

///|
fn natural64(value : Json) -> Int64 raise {
  let text = string(value)
  let n = @string.parse_int64(text)
  if n < 0L || n.to_string() != text {
    raise @model.Invalid("expected canonical nonnegative Int64 string")
  }
  n
}

///|
fn boolean(value : Json) -> Bool raise {
  @json.from_json(value)
}

///|
fn parse_status(value : Json) -> @budget.Status raise {
  let m = object(value)
  match string(field(m, "kind")) {
    "complete_in_domain" => {
      only(m, ["kind"])
      @budget.CompleteInDomain
    }
    "partial" => {
      only(m, ["kind", "reason"])
      let reason = string(field(m, "reason"))
      if reason.is_empty() {
        raise @model.Invalid("empty partial reason")
      }
      @budget.Partial(reason)
    }
    _ => raise @model.Invalid("invalid discovery status")
  }
}

///|
fn parse_limits(value : Json) -> @budget.Limits raise {
  let m = object(value)
  only(m, [
    "max_lhs", "max_ucc_width", "max_candidates", "max_work", "max_results",
  ])
  {
    max_lhs: natural(field(m, "max_lhs")),
    max_ucc_width: natural(field(m, "max_ucc_width")),
    max_candidates: natural(field(m, "max_candidates")),
    max_work: natural64(field(m, "max_work")),
    max_results: natural(field(m, "max_results")),
  }
}

///|
fn parse_usage(value : Json) -> @budget.Usage raise {
  let m = object(value)
  only(m, ["candidates", "work", "results", "partitions", "cache_hits"])
  {
    candidates: natural(field(m, "candidates")),
    work: natural64(field(m, "work")),
    results: natural(field(m, "results")),
    partitions: natural64(field(m, "partitions")),
    cache_hits: natural64(field(m, "cache_hits")),
  }
}

///|
fn parse_deletions(value : Json) -> Array[@dependency.Deletion] raise {
  array(value).map(v => {
    let m = object(v)
    only(m, ["removed", "pair"])
    let p = object(field(m, "pair"))
    only(p, ["first", "second"])
    {
      removed: string(field(m, "removed")),
      pair: {
        first: string(field(p, "first")),
        second: string(field(p, "second")),
      },
    }
  })
}

///|
fn require_proven(m : Map[String, Json]) -> Unit raise {
  if string(field(m, "minimality")) != "proven" {
    raise @model.Invalid("only proven minimality certificates are accepted")
  }
}

///|
fn parse_table_report(value : Json) -> @engine.Discovery raise {
  let m = object(value)
  only(m, [
    "table_id", "row_count", "column_count", "null_policy", "status", "fd_complete",
    "ucc_complete", "limits", "usage", "degenerate", "fds", "uccs",
  ])
  let null_policy = match string(field(m, "null_policy")) {
    "reject" => @model.RejectNull
    "equal" => @model.NullAsValue
    _ => raise @model.Invalid("invalid null policy")
  }
  let fds : Array[@dependency.Fd] = array(field(m, "fds")).map(v => {
    let f = object(v)
    only(f, ["lhs", "rhs", "minimality", "deletions"])
    require_proven(f)
    {
      lhs: strings(field(f, "lhs")),
      rhs: string(field(f, "rhs")),
      deletions: parse_deletions(field(f, "deletions")),
    }
  })
  let uccs : Array[@unique.Ucc] = array(field(m, "uccs")).map(v => {
    let k = object(v)
    only(k, ["columns", "minimality", "deletions"])
    require_proven(k)
    {
      columns: strings(field(k, "columns")),
      deletions: parse_deletions(field(k, "deletions")),
    }
  })
  let result : @engine.Discovery = {
    table_id: string(field(m, "table_id")),
    row_count: natural(field(m, "row_count")),
    column_count: natural(field(m, "column_count")),
    null_policy,
    status: parse_status(field(m, "status")),
    fd_complete: boolean(field(m, "fd_complete")),
    ucc_complete: boolean(field(m, "ucc_complete")),
    limits: parse_limits(field(m, "limits")),
    usage: parse_usage(field(m, "usage")),
    degenerate: boolean(field(m, "degenerate")),
    fds,
    uccs,
  }
  if result.usage.candidates > result.limits.max_candidates ||
    result.usage.work > result.limits.max_work ||
    result.usage.results > result.limits.max_results ||
    result.usage.results.to_int64() !=
    fds.length().to_int64() + uccs.length().to_int64() {
    raise @model.Invalid("inconsistent report counters")
  }
  let finished = result.fd_complete && result.ucc_complete
  if (result.status is @budget.CompleteInDomain) != finished ||
    (result.ucc_complete && !result.fd_complete) ||
    (!result.fd_complete && !uccs.is_empty()) {
    raise @model.Invalid("inconsistent report completion flags")
  }
  result
}

///|
pub fn parse_discovery_report(input : String) -> EvidenceReport raise {
  let root = object(parse_json(input))
  only(root, ["schema_version", "status", "tables"])
  if field(root, "schema_version") != Json::number(1.0) {
    raise @model.Invalid("schema_version must be 1")
  }
  let tables = array(field(root, "tables")).map(parse_table_report)
  let seen = Map([])
  for t in tables {
    if t.table_id.is_empty() || seen.contains(t.table_id) {
      raise @model.Invalid("empty or duplicate report table ID")
    }
    seen[t.table_id] = true
  }
  let status = parse_status(field(root, "status"))
  if (status is @budget.CompleteInDomain) !=
    tables.all(t => t.status is @budget.CompleteInDomain) {
    raise @model.Invalid("inconsistent envelope status")
  }
  { status, tables, }
}

///|
fn ordered_ids(ids : Array[String]) -> Bool {
  for i in 0..<ids.length() {
    if ids[i].is_empty() || (i > 0 && ids[i - 1].lexical_compare(ids[i]) >= 0) {
      return false
    }
  }
  true
}

///|
/// Replay independent validators and every supplied row-pair certificate.
/// The absence of omitted rules and the historical execution are not verified.
pub fn recheck_report(
  tables : Array[@model.Table],
  report : EvidenceReport,
) -> Json {
  let issues : Array[Json] = []
  let mut checked_fds = 0
  let mut checked_uccs = 0
  fn issue(table_id : String, path : String, message : String) -> Unit {
    issues.push({ "table_id": table_id, "path": path, "message": message })
  }
  for t in tables {
    if !report.tables.any(r => r.table_id == t.id) {
      issue(t.id, "tables", "missing table report")
    }
  }
  for r in report.tables {
    let candidates = tables.filter(t => t.id == r.table_id)
    if candidates.length() != 1 {
      issue(r.table_id, "table_id", "expected exactly one matching input table")
      continue
    }
    let t = candidates[0]
    if t.row_count() != r.row_count ||
      t.column_count() != r.column_count ||
      t.policy != r.null_policy ||
      r.degenerate != (t.row_count() <= 1) {
      issue(t.id, "metadata", "snapshot metadata differs")
    }
    let seen_fds : Map[Array[String], Bool] = Map([])
    for i, f in r.fds {
      checked_fds += 1
      let key = f.lhs.copy()
      key.push(f.rhs)
      let path = "fds[\{i}]"
      if seen_fds.contains(key) {
        issue(t.id, path, "duplicate dependency")
      }
      seen_fds[key] = true
      if !ordered_ids(f.lhs) || f.lhs.length() > r.limits.max_lhs {
        issue(t.id, path, "invalid determinant order or search width")
      }
      let valid = @engine.verify_fd(t, f) catch { _ => false }
      if !valid {
        issue(t.id, path, "rule or minimality evidence failed")
      }
    }
    let seen_uccs : Map[Array[String], Bool] = Map([])
    for i, k in r.uccs {
      checked_uccs += 1
      let path = "uccs[\{i}]"
      if seen_uccs.contains(k.columns) {
        issue(t.id, path, "duplicate unique combination")
      }
      seen_uccs[k.columns] = true
      if !ordered_ids(k.columns) || k.columns.length() > r.limits.max_ucc_width {
        issue(t.id, path, "invalid combination order or search width")
      }
      let valid = @engine.verify_ucc(t, k) catch { _ => false }
      if !valid {
        issue(t.id, path, "rule or minimality evidence failed")
      }
    }
  }
  {
    "schema_version": 1,
    "status": { "kind": "rechecked" },
    "valid": issues.is_empty(),
    "completeness_verified": false,
    "reported_status": status(report.status),
    "checked_fds": checked_fds,
    "checked_uccs": checked_uccs,
    "issues": issues,
  }
}
