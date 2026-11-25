///|
/// Retain only integer determinants indexed by dependent column.
pub struct Searcher {
  priv idx : @partition.Index
  priv columns : Array[@model.Column]
  priv known : Array[Array[Array[Int32]]]
  priv sink : Array[Fd]
}

///|
/// A caller may read the sink while stepping, but must leave its contents intact.
pub fn searcher(idx : @partition.Index, sink : Array[Fd]) -> Searcher raise {
  if !sink.is_empty() {
    raise @model.Invalid("discovery sink must initially be empty")
  }
  let width = idx.table.column_count()
  idx.meter.charge(width.to_int64() + 1L)
  {
    idx,
    columns: idx.table.columns(),
    known: Array::makei(width, _ => []),
    sink,
  }
}

///|
fn sorted_subset(
  lhs : Array[Int32],
  candidate : Array[Int32],
  meter : @budget.Meter,
) -> Bool raise @budget.Exhausted {
  if lhs.length() > candidate.length() {
    return false
  }
  let mut at = 0
  for col in candidate {
    if at == lhs.length() {
      return true
    }
    meter.charge(1L)
    if lhs[at] < col {
      return false
    }
    if lhs[at] == col {
      at += 1
    }
  }
  at == lhs.length()
}

///|
/// Evaluate one candidate and append an independently checkable minimal result.
pub fn Searcher::consider(
  self : Searcher,
  x : Array[Int32],
  rhs : Int32,
) -> Unit raise {
  validate_candidate(self.columns.length(), x, rhs)
  let meter = self.idx.meter
  meter.candidate()
  for known in self.known[rhs] {
    meter.charge(1L)
    if sorted_subset(known, x, meter) {
      return
    }
  }
  if prove(self.idx, self.columns, x, rhs) is Some(rule) {
    self.known[rhs].push(x.copy())
    self.sink.push(rule)
  }
}
