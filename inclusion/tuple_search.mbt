///|
fn TupleSearch::emit(
  self : TupleSearch,
  source : TupleTable,
  target : TupleTable,
  mapping : Array[(Int32, Int32)],
  counts : Containment,
) -> Unit raise @budget.Exhausted {
  if self.options.target_unique_only && !counts.target_unique {
    return
  }
  self.meter.charge(mapping.length().to_int64() * 2L)
  self.meter.result()
  self.relations.push({
    source_table: source.id,
    source_columns: mapping.map(p => source.columns[p.0]),
    target_table: target.id,
    target_columns: mapping.map(p => target.columns[p.1]),
    source_distinct: counts.source_distinct,
    target_distinct: counts.target_distinct,
    target_unique: counts.target_unique,
  })
}

///|
fn TupleSearch::search_pair(
  self : TupleSearch,
  source : TupleTable,
  target : TupleTable,
) -> Unit raise @budget.Exhausted {
  self.meter.charge(source.columns.length().to_int64() + 1L)
  let unary = Array::makei(source.columns.length(), _ => [])
  let mut level = []
  for from in 0..<source.columns.length() {
    for to in 0..<target.columns.length() {
      self.meter.candidate()
      let mapping = [(from, to)]
      if self.containment(source, target, mapping) is Some(_) {
        unary[from].push(to)
        level.push(mapping)
      }
    }
  }
  let maximum = Int32::min(
    self.options.max_width,
    Int32::min(source.columns.length(), target.columns.length()),
  )
  for width in 2..<=maximum {
    if level.is_empty() {
      break
    }
    level = self.extend_level(source, target, unary, level, width < maximum)
  }
}

///|
fn TupleSearch::extend_level(
  self : TupleSearch,
  source : TupleTable,
  target : TupleTable,
  unary : Array[Array[Int32]],
  level : Array[Array[(Int32, Int32)]],
  retain : Bool,
) -> Array[Array[(Int32, Int32)]] raise @budget.Exhausted {
  let check_projections = level[0].length() > 1
  let known : Map[Array[(Int32, Int32)], Bool] = Map([])
  if check_projections {
    for mapping in level {
      self.meter.charge(mapping.length().to_int64() + 1L)
      known[mapping] = true
    }
  }
  let next = []
  for prefix in level {
    let start = prefix[prefix.length() - 1].0 + 1
    for from in start..<unary.length() {
      self.meter.charge(1L)
      for to in unary[from] {
        self.meter.charge(prefix.length().to_int64() + 1L)
        if prefix.any(p => p.1 == to) {
          continue
        }
        self.meter.candidate()
        let candidate = prefix + [(from, to)]
        if check_projections && !self.projections_hold(known, candidate) {
          self.pruned += 1
          continue
        }
        let result = self.containment(source, target, candidate)
        self.checked += 1
        if result is Some(counts) {
          self.emit(source, target, candidate, counts)
          if retain {
            next.push(candidate)
          }
        }
      }
    }
  }
  next
}

///|
fn TupleSearch::projections_hold(
  self : TupleSearch,
  known : Map[Array[(Int32, Int32)], Bool],
  mapping : Array[(Int32, Int32)],
) -> Bool raise @budget.Exhausted {
  // The prefix without the appended pair is already in the previous level.
  let size = mapping.length() - 1
  for removed in 0..<size {
    self.meter.charge(size.to_int64() + 1L)
    let projected = Array::makei(size, i => {
      if i < removed {
        mapping[i]
      } else {
        mapping[i + 1]
      }
    })
    if !known.contains(projected) {
      return false
    }
  }
  true
}
