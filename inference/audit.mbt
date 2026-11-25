///|
/// An independently derived proof that a declaration can be simplified.
pub(all) struct Reduction {
  rule_index : Int32
  removed_column : String?
  proof : Array[Step]
}

///|
pub(all) enum MinimalityCheck {
  Irreducible
  Reducible(Reduction)
  MinimalityUnchecked
}

///|
pub(all) struct CoverAudit {
  comparison : TheoryComparison
  minimality : MinimalityCheck
  status : @budget.Status
  usage : @budget.Usage
}

///|
fn Theory::check_minimality(
  self : Theory,
  m : @budget.Meter,
) -> MinimalityCheck raise @budget.Exhausted {
  for i, rule in self.premises {
    m.candidate()
    let without_rule = self.scan(rule.lhs, rule.rhs, m, excluded=Some(i))
    if without_rule.known[rule.rhs] {
      m.result()
      return Reducible({
        rule_index: i,
        removed_column: None,
        proof: without_rule.proof,
      })
    }
    for at, column in rule.lhs {
      m.candidate()
      m.charge(rule.lhs.length().to_int64())
      let shorter = self.scan(omit_column(rule.lhs, at), rule.rhs, m)
      if shorter.known[rule.rhs] {
        m.result()
        return Reducible({
          rule_index: i,
          removed_column: Some(self.columns[column]),
          proof: shorter.proof,
        })
      }
    }
  }
  Irreducible
}

///|
/// Independently check equivalence and both minimality conditions under one budget.
pub fn Theory::audit_cover(
  self : Theory,
  candidate : Theory,
  limits~ : @budget.Limits = @budget.defaults(),
) -> CoverAudit raise @model.InputError {
  self.check_schema(candidate)
  let m = @budget.meter(limits)
  let comparison = self.compare_with_meter(candidate, m)
  let mut minimality = MinimalityUnchecked
  let status = if comparison.status is @budget.CompleteInDomain {
    try {
      minimality = candidate.check_minimality(m)
      @budget.CompleteInDomain
    } catch {
      @budget.Exhausted(reason) => @budget.Partial(reason)
    }
  } else {
    comparison.status
  }
  { comparison, minimality, status, usage: m.usage(), }
}

///|
/// Check a reduction against the exact premise order of the candidate theory.
pub fn Theory::verify_reduction(self : Theory, reduction : Reduction) -> Bool {
  let i = reduction.rule_index
  if i < 0 || i >= self.premises.length() {
    return false
  }
  let rule = self.describe(self.premises[i])
  let proof = reduction.proof
  match reduction.removed_column {
    Some(col) =>
      rule.lhs.contains(col) &&
      self.verify_entailment(rule.lhs.filter(p => p != col), rule.rhs, proof)
    None =>
      proof.all(step => step.rule_index != i) &&
      self.verify_entailment(rule.lhs, rule.rhs, proof)
  }
}
