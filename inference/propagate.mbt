///|
/// Consume a seed agenda in place, optionally stopping after a goal is reached.
/// A callback must finish before a newly derived column is added to the agenda.
fn Theory::propagate(
  self : Theory,
  agenda : Array[Int32],
  meter : @budget.Meter,
  goal~ : Int32? = None,
  enabled~ : (Int32) -> Bool = _ => true,
  on_rule~ : (Int32, Int32, Bool) -> Unit raise @budget.Exhausted = (_, _, _) => {
    ()
  },
) -> Bool raise @budget.Exhausted {
  meter.charge(
    self.columns.length().to_int64() +
    self.premises.length().to_int64() +
    agenda.length().to_int64() +
    1L,
  )
  let known = Array::make(self.columns.length(), false)
  for p in agenda {
    known[p] = true
  }
  if goal is Some(target) && known[target] {
    return true
  }
  let remaining = self.premises.map(rule => rule.lhs.length())
  fn fire(i : Int32) -> Bool raise @budget.Exhausted {
    let rhs = self.premises[i].rhs
    on_rule(i, rhs, !known[rhs])
    if !known[rhs] {
      known[rhs] = true
      agenda.push(rhs)
    }
    goal is Some(target) && target == rhs
  }
  for i in self.constants {
    if enabled(i) && fire(i) {
      return true
    }
  }
  let mut cursor = 0
  while cursor < agenda.length() {
    meter.charge(1L)
    let column = agenda[cursor]
    cursor += 1
    for i in self.consumers[column] {
      meter.charge(1L)
      if enabled(i) {
        remaining[i] -= 1
        if remaining[i] == 0 && fire(i) {
          return true
        }
      }
    }
  }
  false
}
