///|
pub(all) struct Rule {
  lhs : Array[String]
  rhs : String
}

///|
priv struct CompiledRule {
  lhs : Array[Int32]
  rhs : Int32
}

///|
/// Immutable FD premises and reverse incidence index for repeated closure queries.
pub struct Theory {
  priv columns : Array[String]
  priv positions : Map[String, Int32]
  priv premises : Array[CompiledRule]
  priv consumers : Array[Array[Int32]]
  priv constants : Array[Int32]
}

///|
fn positions_of(
  positions : Map[String, Int32],
  columns : Array[String],
) -> Array[Int32] raise @model.InputError {
  let seen : Map[Int32, Bool] = Map([])
  let result = []
  for col in columns {
    match positions.get(col) {
      Some(p) => {
        if seen.contains(p) {
          raise @model.Invalid("repeated inference column: " + col)
        }
        seen[p] = true
        result.push(p)
      }
      None => raise @model.Invalid("unknown inference column: " + col)
    }
  }
  result.sort()
  result
}

///|
/// Compile declared singleton-RHS FDs. Premise indices follow input order.
pub fn theory(
  columns : Array[String],
  rules : Array[Rule],
) -> Theory raise @model.InputError {
  let ordered = columns.copy()
  ordered.sort_by((a, b) => a.lexical_compare(b))
  let positions : Map[String, Int32] = Map([])
  for i, id in ordered {
    if id.is_empty() || positions.contains(id) {
      raise @model.Invalid("empty or duplicate inference column")
    }
    positions[id] = i
  }
  let premises : Array[CompiledRule] = []
  let consumers = Array::makei(ordered.length(), _ => [])
  let constants = []
  let seen : Map[(Array[Int32], Int32), Bool] = Map([])
  for i, rule in rules {
    let lhs = positions_of(positions, rule.lhs)
    let rhs = match positions.get(rule.rhs) {
      Some(pos) => pos
      None => raise @model.Invalid("unknown inference RHS: " + rule.rhs)
    }
    if lhs.contains(rhs) {
      raise @model.Invalid("inference requires a nontrivial FD")
    }
    let key = (lhs, rhs)
    if seen.contains(key) {
      raise @model.Invalid("duplicate inference rule")
    }
    seen[key] = true
    premises.push({ lhs, rhs, })
    if lhs.is_empty() {
      constants.push(i)
    }
    for p in lhs {
      consumers[p].push(i)
    }
  }
  { columns: ordered, positions, premises, consumers, constants, }
}

///|
/// Return copies so callers cannot mutate the compiled theory.
pub fn Theory::rules(self : Theory) -> Array[Rule] {
  self.premises.map(rule => {
    lhs: rule.lhs.map(p => self.columns[p]),
    rhs: self.columns[rule.rhs],
  })
}
