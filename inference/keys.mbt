///|
pub(all) struct KeyDeletion {
  removed : String
  missing : String
  agreement : Array[String]
}

///|
/// A minimal set whose closure is the entire schema under this theory.
pub(all) struct SchemaKey {
  columns : Array[String]
  proof : Array[Step]
  deletions : Array[KeyDeletion]
}

///|
pub(all) struct SchemaKeys {
  keys : Array[SchemaKey]
  max_width : Int32
  status : @budget.Status
  usage : @budget.Usage
}

///|
fn Theory::key_deletions(
  self : Theory,
  columns : Array[Int32],
  m : @budget.Meter,
) -> Array[KeyDeletion] raise @budget.Exhausted {
  let deletions = []
  for at, col in columns {
    m.charge(columns.length().to_int64())
    let agenda = omit_column(columns, at)
    ignore(self.propagate(agenda, m))
    m.charge(self.columns.length().to_int64() + agenda.length().to_int64())
    let present = Array::make(self.columns.length(), false)
    for p in agenda {
      present[p] = true
    }
    let agreement = []
    let mut missing = None
    for p, id in self.columns {
      if present[p] {
        agreement.push(id)
      } else if missing is None {
        missing = Some(id)
      }
    }
    guard missing is Some(missing) else {
      abort("a minimal schema key deletion must lose an attribute")
    }
    deletions.push({ removed: self.columns[col], missing, agreement, })
  }
  deletions
}

///|
fn Theory::search_keys(
  self : Theory,
  max_width : Int32,
  results : Array[SchemaKey],
  m : @budget.Meter,
) -> Unit raise {
  let width = self.columns.length()
  m.charge(width.to_int64() + self.premises.length().to_int64() + 1L)
  let can_derive = Array::make(width, false)
  for rule in self.premises {
    can_derive[rule.rhs] = true
  }
  let required = Array::makei(width, i => i).filter(p => !can_derive[p])
  if required.length() > max_width {
    return
  }
  m.candidate()
  let initial = required.copy()
  let prefix = self.expand_key(initial, m)
  if initial.length() == width {
    results.push(self.prove_key(required, prefix, m))
    return
  }
  if required.length() == max_width {
    return
  }
  m.charge(width.to_int64() + initial.length().to_int64())
  let known = Array::make(width, false)
  for p in initial {
    known[p] = true
  }
  // Every key contains required; columns it already determines are extraneous.
  let optional = Array::makei(width, i => i).filter(p => !known[p])
  let proved : Array[Array[Int32]] = []
  let max_optional = Int32::min(
    max_width - required.length(),
    optional.length(),
  )
  for size in 1..<=max_optional {
    @budget.combinations(optional.length(), size, m, fn(chosen) raise {
      m.candidate()
      m.charge((required.length() + chosen.length()).to_int64() + 1L)
      let extras = chosen.map(i => optional[i])
      let current = required + extras
      for key in proved {
        m.charge(key.length().to_int64() * current.length().to_int64() + 1L)
        if key.all(p => current.contains(p)) {
          return
        }
      }
      m.charge(initial.length().to_int64())
      let agenda = initial + extras
      let proof = self.expand_key(agenda, m)
      if agenda.length() == width {
        m.charge(prefix.length().to_int64() + proof.length().to_int64())
        results.push(self.prove_key(current, prefix + proof, m))
        proved.push(current)
      }
    })
  }
}

///|
fn Theory::expand_key(
  self : Theory,
  agenda : Array[Int32],
  m : @budget.Meter,
) -> Array[Step] raise @budget.Exhausted {
  let proof = []
  ignore(
    self.propagate(agenda, m, on_rule=(i, rhs, fresh) => {
      if fresh {
        proof.push({ rule_index: i, derived: self.columns[rhs], })
      }
    }),
  )
  proof
}

///|
fn Theory::prove_key(
  self : Theory,
  columns : Array[Int32],
  proof : Array[Step],
  m : @budget.Meter,
) -> SchemaKey raise @budget.Exhausted {
  m.charge(columns.length().to_int64())
  columns.sort()
  let deletions = self.key_deletions(columns, m)
  m.result()
  { columns: columns.map(p => self.columns[p]), proof, deletions, }
}

///|
/// Enumerate every minimal determinant of the schema up to limits.max_lhs.
pub fn Theory::schema_keys(
  self : Theory,
  limits~ : @budget.Limits = @budget.defaults(),
) -> SchemaKeys raise {
  let m = @budget.meter(limits)
  let max_width = Int32::min(self.columns.length(), limits.max_lhs)
  let keys = []
  let status = try {
    self.search_keys(max_width, keys, m)
    @budget.CompleteInDomain
  } catch {
    @budget.Exhausted(reason) => @budget.Partial(reason)
    error => raise error
  }
  { keys, max_width, status, usage: m.usage(), }
}

///|
/// Replay closure steps and check one concrete countermodel for each deletion.
pub fn Theory::verify_schema_key(self : Theory, key : SchemaKey) -> Bool {
  guard self.replay_steps(key.columns, key.proof) is Some(known) else {
    return false
  }
  if known.length() != self.columns.length() ||
    key.deletions.length() != key.columns.length() {
    return false
  }
  let seen : Map[String, Bool] = Map([])
  for deletion in key.deletions {
    let removed = deletion.removed
    if seen.contains(removed) ||
      !key.columns.contains(removed) ||
      !self.verify_counterexample(
        key.columns.filter(p => p != removed),
        deletion.missing,
        deletion.agreement,
      ) {
      return false
    }
    seen[removed] = true
  }
  true
}
