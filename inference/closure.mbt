///|
pub(all) struct Step {
  rule_index : Int32
  derived : String
}

///|
pub(all) struct Closure {
  seeds : Array[String]
  attributes : Array[String]
  steps : Array[Step]
  status : @budget.Status
  usage : @budget.Usage
}

///|
/// Propagate attributes through an agenda. Each premise can fire only once.
pub fn Theory::closure(
  self : Theory,
  seeds : Array[String],
  limits~ : @budget.Limits = @budget.defaults(),
) -> Closure raise {
  let initial = positions_of(self.positions, seeds)
  let m = @budget.meter(limits)
  let agenda = initial.copy()
  let steps : Array[Step] = []
  let status = try {
    self.propagate(agenda, m, on_rule=fn(
      i,
      rhs,
      fresh,
    ) -> Unit raise @budget.Exhausted {
      m.candidate()
      if fresh {
        m.result()
        steps.push({ rule_index: i, derived: self.columns[rhs], })
      }
    })
    |> ignore
    @budget.CompleteInDomain
  } catch {
    @budget.Exhausted(reason) => @budget.Partial(reason)
  }
  agenda.sort()
  {
    seeds: initial.map(p => self.columns[p]),
    attributes: agenda.map(p => self.columns[p]),
    steps,
    status,
    usage: m.usage(),
  }
}

///|
fn Theory::replay_steps(
  self : Theory,
  seeds : Array[String],
  steps : Array[Step],
) -> Map[Int32, Bool]? {
  let known : Map[Int32, Bool] = Map([])
  for id in seeds {
    match self.positions.get(id) {
      Some(p) if !known.contains(p) => known[p] = true
      _ => return None
    }
  }
  for step in steps {
    if step.rule_index < 0 || step.rule_index >= self.premises.length() {
      return None
    }
    let rule = self.premises[step.rule_index]
    if step.derived != self.columns[rule.rhs] ||
      known.contains(rule.rhs) ||
      !rule.lhs.all(p => known.contains(p)) {
      return None
    }
    known[rule.rhs] = true
  }
  Some(known)
}

///|
/// Verify each step by replaying premises. Completeness and usage are separate claims.
pub fn Theory::verify_trace(self : Theory, result : Closure) -> Bool {
  guard self.replay_steps(result.seeds, result.steps) is Some(known) else {
    return false
  }
  if known.length() != result.attributes.length() {
    return false
  }
  let seen : Map[Int32, Bool] = Map([])
  for id in result.attributes {
    match self.positions.get(id) {
      Some(p) if known.contains(p) && !seen.contains(p) => seen[p] = true
      _ => return false
    }
  }
  true
}

///|
/// Keep only the found derivation steps needed for a target, in executable order.
/// None means the trace did not derive that target.
pub fn Theory::explain(
  self : Theory,
  result : Closure,
  target : String,
) -> Array[Step]? raise @model.InputError {
  let goal = match self.positions.get(target) {
    Some(p) => p
    None => raise @model.Invalid("unknown inference target: " + target)
  }
  if !self.verify_trace(result) {
    raise @model.Invalid("cannot explain an invalid inference trace")
  }
  if !result.attributes.contains(target) {
    return None
  }
  Some(self.target_steps(result.steps, goal))
}

///|
fn Theory::target_steps(
  self : Theory,
  steps : Array[Step],
  goal : Int32,
) -> Array[Step] {
  let needed = Array::make(self.columns.length(), false)
  needed[goal] = true
  let proof = []
  for n in 0..<steps.length() {
    let step = steps[steps.length() - 1 - n]
    let rule = self.premises[step.rule_index]
    if needed[rule.rhs] {
      proof.push(step)
      for p in rule.lhs {
        needed[p] = true
      }
    }
  }
  proof.rev_in_place()
  proof
}
