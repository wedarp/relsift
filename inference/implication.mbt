///|
/// A derivation, a two-row counterexample, or an inconclusive bounded search.
pub(all) enum Outcome {
  Entailed(Array[Step])
  Refuted(Array[String])
  Undetermined
}

///|
pub(all) struct Implication {
  lhs : Array[String]
  rhs : String
  outcome : Outcome
  status : @budget.Status
  usage : @budget.Usage
}

///|
/// Decide whether the premises imply lhs -> rhs. A refutation lists exactly
/// the columns on which two hypothetical rows agree.
pub fn Theory::implies(
  self : Theory,
  lhs : Array[String],
  rhs : String,
  limits~ : @budget.Limits = @budget.defaults(),
) -> Implication raise {
  if !self.positions.contains(rhs) {
    raise @model.Invalid("unknown inference target: " + rhs)
  }
  let result = self.closure(lhs, limits~)
  let outcome = if result.attributes.contains(rhs) {
    // The closure producer has already established these steps.
    Entailed(self.target_steps(result.steps, self.positions[rhs]))
  } else if result.status is @budget.CompleteInDomain {
    Refuted(result.attributes)
  } else {
    Undetermined
  }
  {
    lhs: result.seeds,
    rhs,
    outcome,
    status: result.status,
    usage: result.usage,
  }
}

///|
/// Replay a proof and check that its conclusion is present.
pub fn Theory::verify_entailment(
  self : Theory,
  lhs : Array[String],
  rhs : String,
  proof : Array[Step],
) -> Bool {
  match (self.positions.get(rhs), self.replay_steps(lhs, proof)) {
    (Some(target), Some(known)) => known.contains(target)
    _ => false
  }
}

///|
/// Check a compact two-row model without running the closure algorithm.
pub fn Theory::verify_counterexample(
  self : Theory,
  lhs : Array[String],
  rhs : String,
  agreement : Array[String],
) -> Bool {
  let agreed = positions_of(self.positions, agreement) catch {
    _ => return false
  }
  let seeds = positions_of(self.positions, lhs) catch { _ => return false }
  let target = match self.positions.get(rhs) {
    Some(p) => p
    None => return false
  }
  let same = Array::make(self.columns.length(), false)
  for p in agreed {
    same[p] = true
  }
  if same[target] || !seeds.all(p => same[p]) {
    return false
  }
  self.premises.all(rule => same[rule.rhs] || !rule.lhs.all(p => same[p]))
}
