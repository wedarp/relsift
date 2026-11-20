///|
#derive(Eq, @debug.Debug)
pub(all) struct Discovery {
  table_id : String
  row_count : Int32
  column_count : Int32
  limits : @budget.Limits
  status : @budget.Status
  fd_complete : Bool
  ucc_complete : Bool
  fds : Array[@dependency.Fd]
  uccs : Array[@unique.Ucc]
  usage : @budget.Usage
  degenerate : Bool
}

///|
/// FD and UCC searches share one index and budget. Width limits define the domain.
pub fn discover(
  t : @model.Table,
  limits~ : @budget.Limits = @budget.defaults(),
) -> Discovery raise {
  let meter = @budget.meter(limits)
  let fds = []
  let uccs = []
  let mut fd_complete = false
  let mut ucc_complete = false
  let status = try {
    let idx = @partition.index(t, meter)
    @dependency.discover(idx, fds)
    fd_complete = true
    @unique.discover(idx, uccs)
    ucc_complete = true
    @budget.CompleteInDomain
  } catch {
    @budget.Exhausted(reason) => @budget.Partial(reason)
    error => raise error
  }
  {
    table_id: t.id,
    row_count: t.row_count(),
    column_count: t.column_count(),
    limits,
    status,
    fd_complete,
    ucc_complete,
    fds,
    uccs,
    usage: meter.usage(),
    degenerate: t.row_count() <= 1,
  }
}

///|
/// Check rule validity, one evidence item per LHS column, and the exact row IDs.
pub fn verify_fd(t : @model.Table, rule : @dependency.Fd) -> Bool raise {
  if !@verify.fd(t, rule.lhs, rule.rhs).holds ||
    rule.deletions.length() != rule.lhs.length() {
    return false
  }
  let seen = []
  for evidence in rule.deletions {
    if !rule.lhs.contains(evidence.removed) || seen.contains(evidence.removed) {
      return false
    }
    seen.push(evidence.removed)
    if !@verify.check_pair(
        t,
        rule.lhs.filter(c => c != evidence.removed),
        evidence.pair,
        rhs=Some(rule.rhs),
      ) {
      return false
    }
  }
  true
}

///|
pub fn verify_ucc(t : @model.Table, rule : @unique.Ucc) -> Bool raise {
  if !@verify.unique(t, rule.columns).holds ||
    rule.deletions.length() != rule.columns.length() {
    return false
  }
  let seen = []
  for evidence in rule.deletions {
    if !rule.columns.contains(evidence.removed) ||
      seen.contains(evidence.removed) {
      return false
    }
    seen.push(evidence.removed)
    if !@verify.check_pair(
        t,
        rule.columns.filter(c => c != evidence.removed),
        evidence.pair,
      ) {
      return false
    }
  }
  true
}

///|
#deprecated
pub extend Discovery with Eq::{equal, not_equal}

///|
#deprecated
pub extend Discovery with @debug.Debug::{to_repr}
