///|
#derive(Eq, @debug.Debug)
pub(all) struct Ucc {
  columns : Array[String]
  deletions : Array[@dependency.Deletion]
}

///|
/// Row multiplicity is preserved by the index. Empty-set uniqueness is included.
pub fn discover(idx : @partition.Index, out : Array[Ucc]) -> Unit raise {
  if !out.is_empty() {
    raise @model.Invalid("discovery sink must initially be empty")
  }
  let cols = idx.table.columns()
  let m = idx.meter
  let max_width = Int32::min(cols.length(), m.limits.max_ucc_width)
  for size in 0..<=max_width {
    @budget.combinations(cols.length(), size, m, fn(x) raise {
      consider(idx, x, out)
    })
  }
}

///|
pub fn consider(
  idx : @partition.Index,
  x : Array[Int32],
  out : Array[Ucc],
) -> Unit raise {
  let cols = idx.table.columns()
  for i, c in x {
    if i > 0 && x[i - 1] >= c {
      raise @model.Invalid("UCC positions must be strictly increasing")
    }
  }
  if x.any(c => c < 0 || c >= cols.length()) {
    raise @model.Invalid("invalid UCC candidate positions")
  }
  let m = idx.meter
  m.candidate()
  let names = x.map(c => cols[c].id)
  for known in out {
    m.charge(known.columns.length().to_int64() + 1L)
    if known.columns.all(c => names.contains(c)) {
      return
    }
  }
  if !idx.unique(x) {
    return
  }
  let deletions : Array[@dependency.Deletion] = []
  for removed in x {
    let parent = x.filter(c => c != removed)
    match idx.witness(parent) {
      Some(pair) => deletions.push({ removed: cols[removed].id, pair, })
      None => return
    }
  }
  m.result()
  out.push({ columns: names, deletions, })
}

///|
#deprecated
pub extend Ucc with Eq::{equal, not_equal}

///|
#deprecated
pub extend Ucc with @debug.Debug::{to_repr}
