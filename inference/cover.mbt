///|
/// Describe a committed change to the working set, in execution order.
pub(all) enum CoverEdit {
  RemovedColumn(Rule, String)
  RemovedRule(Rule)
}

///|
pub(all) struct Cover {
  rules : Array[Rule]
  edits : Array[CoverEdit]
  status : @budget.Status
  usage : @budget.Usage
}

///|
fn compare_rules(a : CompiledRule, b : CompiledRule) -> Int32 {
  for i in 0..<Int32::min(a.lhs.length(), b.lhs.length()) {
    let order = a.lhs[i].compare(b.lhs[i])
    if order != 0 {
      return order
    }
  }
  let width = a.lhs.length().compare(b.lhs.length())
  if width != 0 {
    width
  } else {
    a.rhs.compare(b.rhs)
  }
}

///|
/// Remove a member of a sorted determinant using its current offset.
fn omit_column(lhs : Array[Int32], at : Int32) -> Array[Int32] {
  Array::makei(lhs.length() - 1, i => if i < at { lhs[i] } else { lhs[i + 1] })
}

///|
fn Theory::shorten(
  self : Theory,
  working : Array[CompiledRule],
  active : Array[Bool],
  edits : Array[CoverEdit],
  m : @budget.Meter,
) -> Unit raise @budget.Exhausted {
  let names : Map[(Array[Int32], Int32), Bool] = Map([])
  for rule in working {
    m.charge(rule.lhs.length().to_int64() + 1L)
    names[(rule.lhs, rule.rhs)] = true
  }
  for i in 0..<working.length() {
    let mut at = 0
    while at < working[i].lhs.length() {
      let rule = working[i]
      let rhs = rule.rhs
      m.candidate()
      m.charge(rule.lhs.length().to_int64())
      let lhs = omit_column(rule.lhs, at)
      // Earlier edits preserve the closure, so the original index answers
      // every shortening query. A failed deletion stays failed on subsets.
      if !self.propagate(lhs.copy(), m, goal=Some(rhs)) {
        at += 1
        continue
      }
      m.charge(rule.lhs.length().to_int64() + lhs.length().to_int64())
      m.result()
      names.remove((rule.lhs, rhs))
      if names.contains((lhs, rhs)) {
        active[i] = false
        edits.push(RemovedRule(self.describe(rule)))
        break
      }
      edits.push(RemovedColumn(self.describe(rule), self.columns[rule.lhs[at]]))
      working[i] = { lhs, rhs, }
      names[(lhs, rhs)] = true
    }
  }
}

///|
fn Theory::remove_redundant(
  self : Theory,
  working : Array[CompiledRule],
  active : Array[Bool],
  edits : Array[CoverEdit],
  m : @budget.Meter,
) -> Unit raise @budget.Exhausted {
  m.charge(self.columns.length().to_int64() + 1L)
  for rule in working {
    m.charge(rule.lhs.length().to_int64() + 1L)
  }
  let index = index_premises(self.columns, self.positions, working)
  for i, rule in working {
    m.charge(1L)
    if !active[i] {
      continue
    }
    m.candidate()
    if index.propagate(rule.lhs.copy(), m, goal=Some(rule.rhs), enabled=j => {
        j != i && active[j]
      }) {
      m.result()
      active[i] = false
      edits.push(RemovedRule(self.describe(rule)))
    }
  }
}

///|
/// Return an equivalent singleton-RHS cover, irreducible when complete.
/// Each edit is committed only after proof and result accounting finish.
pub fn Theory::minimal_cover(
  self : Theory,
  limits~ : @budget.Limits = @budget.defaults(),
) -> Cover raise @model.InputError {
  let m = @budget.meter(limits)
  let working = self.premises.copy()
  working.sort_by(compare_rules)
  let active = Array::make(working.length(), true)
  let edits = []
  let status = try {
    self.shorten(working, active, edits, m)
    self.remove_redundant(working, active, edits, m)
    @budget.CompleteInDomain
  } catch {
    @budget.Exhausted(reason) => @budget.Partial(reason)
  }
  let retained = []
  for i, rule in working {
    if active[i] {
      retained.push(rule)
    }
  }
  retained.sort_by(compare_rules)
  {
    rules: retained.map(r => self.describe(r)),
    edits,
    status,
    usage: m.usage(),
  }
}
