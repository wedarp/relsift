///|
priv struct Scan {
  known : Array[Bool]
  proof : Array[Step]
}

///|
/// Independent fixed-point scan used to audit results of indexed propagation.
fn Theory::scan(
  self : Theory,
  seeds : Array[Int32],
  goal : Int32,
  m : @budget.Meter,
  excluded~ : Int32? = None,
) -> Scan raise @budget.Exhausted {
  m.charge(self.columns.length().to_int64() + seeds.length().to_int64() + 1L)
  let known = Array::make(self.columns.length(), false)
  let proof = []
  for p in seeds {
    known[p] = true
  }
  while !known[goal] {
    m.charge(1L)
    let before = proof.length()
    for i, rule in self.premises {
      m.charge(1L)
      if (excluded is Some(skip) && i == skip) || known[rule.rhs] {
        continue
      }
      m.charge(rule.lhs.length().to_int64())
      if rule.lhs.all(p => known[p]) {
        known[rule.rhs] = true
        proof.push({ rule_index: i, derived: self.columns[rule.rhs], })
        if rule.rhs == goal {
          break
        }
      }
    }
    if proof.length() == before {
      break
    }
  }
  { known, proof, }
}
