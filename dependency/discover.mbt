///|
#derive(Eq, @debug.Debug)
pub(all) struct Deletion {
  removed : String
  pair : @verify.Pair
}

///|
#derive(Eq, @debug.Debug)
pub(all) struct Fd {
  lhs : Array[String]
  rhs : String
  deletions : Array[Deletion]
}

///|
/// Append only fully proved minimal nontrivial FDs, in increasing LHS width.
/// Exhausted propagates; the caller may keep the already appended results.
pub fn discover(idx : @partition.Index, out : Array[Fd]) -> Unit raise {
  if !out.is_empty() {
    raise @model.Invalid("discovery sink must initially be empty")
  }
  let cols = idx.table.columns()
  let m = idx.meter
  let width = cols.length()
  let max_lhs = Int32::min(m.limits.max_lhs, Int32::max(0, width - 1))
  for size in 0..<=max_lhs {
    @budget.combinations(width, size, m, fn(x) raise {
      for a in 0..<width {
        if x.contains(a) {
          continue
        }
        m.candidate()
        let names = x.map(c => cols[c].id)
        let mut pruned = false
        for known in out {
          m.charge(known.lhs.length().to_int64() + 1L)
          if known.rhs == cols[a].id && known.lhs.all(c => names.contains(c)) {
            pruned = true
            break
          }
        }
        if pruned || !idx.fd(x, a) {
          continue
        }
        let deletions = []
        let mut minimal = true
        for removed in x {
          let parent = x.filter(c => c != removed)
          match idx.witness(parent, rhs=Some(a)) {
            Some(pair) => deletions.push({ removed: cols[removed].id, pair, })
            None => {
              minimal = false
              break
            }
          }
        }
        if minimal {
          m.result()
          out.push({ lhs: names, rhs: cols[a].id, deletions, })
        }
      }
    })
  }
}

///|
#deprecated
pub extend Deletion with Eq::{equal, not_equal}

///|
#deprecated
pub extend Deletion with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Fd with Eq::{equal, not_equal}

///|
#deprecated
pub extend Fd with @debug.Debug::{to_repr}
