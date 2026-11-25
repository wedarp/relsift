///|
/// A rule of the target theory refuted by a two-row model of the source theory.
pub(all) struct Separation {
  rule : Rule
  agreement : Array[String]
}

///|
pub(all) enum DirectionalCheck {
  EntailsAll
  Separated(Separation)
  Unchecked
}

///|
pub(all) struct TheoryComparison {
  left_to_right : DirectionalCheck
  right_to_left : DirectionalCheck
  status : @budget.Status
  usage : @budget.Usage
}

///|
fn Theory::check_schema(
  self : Theory,
  other : Theory,
) -> Unit raise @model.InputError {
  if self.columns != other.columns {
    raise @model.Invalid("theories must have the same column IDs")
  }
}

///|
fn Theory::check_direction(
  self : Theory,
  target : Theory,
  m : @budget.Meter,
) -> DirectionalCheck raise @budget.Exhausted {
  for rule in target.premises {
    m.candidate()
    let result = self.scan(rule.lhs, rule.rhs, m)
    if !result.known[rule.rhs] {
      m.charge(self.columns.length().to_int64())
      m.result()
      let agreement = []
      for p, col in self.columns {
        if result.known[p] {
          agreement.push(col)
        }
      }
      return Separated({ rule: target.describe(rule), agreement, })
    }
  }
  EntailsAll
}

///|
fn Theory::compare_with_meter(
  self : Theory,
  other : Theory,
  m : @budget.Meter,
) -> TheoryComparison {
  let mut left_to_right = Unchecked
  let mut right_to_left = Unchecked
  let status = try {
    left_to_right = self.check_direction(other, m)
    right_to_left = other.check_direction(self, m)
    @budget.CompleteInDomain
  } catch {
    @budget.Exhausted(reason) => @budget.Partial(reason)
  }
  { left_to_right, right_to_left, status, usage: m.usage(), }
}

///|
/// Compare declared theories without requiring either set to be minimal.
pub fn Theory::compare(
  self : Theory,
  other : Theory,
  limits~ : @budget.Limits = @budget.defaults(),
) -> TheoryComparison raise @model.InputError {
  self.check_schema(other)
  self.compare_with_meter(other, @budget.meter(limits))
}

///|
/// Validate rule membership on the target side and the model on the source side.
pub fn Theory::verify_separation(
  self : Theory,
  target : Theory,
  witness : Separation,
) -> Bool {
  if self.columns != target.columns {
    return false
  }
  let rule = witness.rule
  let lhs = positions_of(target.positions, rule.lhs) catch { _ => return false }
  guard target.positions.get(rule.rhs) is Some(rhs) else { return false }
  target.premises.any(premise => premise.rhs == rhs && premise.lhs == lhs) &&
  self.verify_counterexample(rule.lhs, rule.rhs, witness.agreement)
}
