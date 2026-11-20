///|
#derive(Eq, @debug.Debug)
pub(all) enum Status {
  CompleteInDomain
  Partial(String)
}

///|
#derive(@debug.Debug)
pub(all) suberror Exhausted {
  Exhausted(String)
}

///|
#derive(Eq, @debug.Debug)
pub(all) struct Limits {
  max_lhs : Int32
  max_ucc_width : Int32
  max_candidates : Int32
  max_work : Int64
  max_results : Int32
}

///|
pub fn defaults() -> Limits {
  {
    max_lhs: 4,
    max_ucc_width: 4,
    max_candidates: 100000,
    max_work: 10000000L,
    max_results: 10000,
  }
}

///|
#derive(Eq, @debug.Debug)
pub(all) struct Usage {
  candidates : Int32
  work : Int64
  results : Int32
  partitions : Int64
  cache_hits : Int64
}

///|
pub struct Meter {
  limits : Limits
  priv mut candidates : Int32
  priv mut work : Int64
  priv mut results : Int32
  priv mut partitions : Int64
  priv mut cache_hits : Int64
}

///|
pub fn meter(limits : Limits) -> Meter raise @model.InputError {
  if limits.max_lhs < 0 ||
    limits.max_ucc_width < 0 ||
    limits.max_candidates < 0 ||
    limits.max_work < 0L ||
    limits.max_results < 0 {
    raise @model.Invalid("negative resource budget")
  }
  { limits, candidates: 0, work: 0L, results: 0, partitions: 0, cache_hits: 0, }
}

///|
pub fn Meter::charge(self : Meter, count : Int64) -> Unit raise Exhausted {
  if count < 0L || count > self.limits.max_work - self.work {
    raise Exhausted("max_work")
  }
  self.work += count
}

///|
pub fn Meter::candidate(self : Meter) -> Unit raise Exhausted {
  if self.candidates >= self.limits.max_candidates {
    raise Exhausted("max_candidates")
  }
  self.charge(1L)
  self.candidates += 1
}

///|
pub fn Meter::result(self : Meter) -> Unit raise Exhausted {
  if self.results >= self.limits.max_results {
    raise Exhausted("max_results")
  }
  self.results += 1
}

///|
pub fn Meter::partition(self : Meter) -> Unit {
  self.partitions += 1
}

///|
pub fn Meter::cache_hit(self : Meter) -> Unit {
  self.cache_hits += 1
}

///|
pub fn Meter::usage(self : Meter) -> Usage {
  {
    candidates: self.candidates,
    work: self.work,
    results: self.results,
    partitions: self.partitions,
    cache_hits: self.cache_hits,
  }
}

///|
/// Lazy fixed-width combinations: no eager allocation of the powerset.
pub fn combinations(
  width : Int32,
  size : Int32,
  meter : Meter,
  visit : (Array[Int32]) -> Unit raise,
) -> Unit raise {
  if width < 0 || size < 0 || size > width {
    raise @model.Invalid("invalid combination dimensions")
  }
  fn walk(start : Int32, chosen : Array[Int32]) -> Unit raise {
    meter.charge(1L)
    if chosen.length() == size {
      visit(chosen.copy())
      return
    }
    let needed = size - chosen.length()
    for c in start..<(width - needed + 1) {
      chosen.push(c)
      walk(c + 1, chosen)
      ignore(chosen.pop())
    }
  }
  walk(0, [])
}

///|
#deprecated
pub extend Status with Eq::{equal, not_equal}

///|
#deprecated
pub extend Status with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Exhausted with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Limits with Eq::{equal, not_equal}

///|
#deprecated
pub extend Limits with @debug.Debug::{to_repr}

///|
#deprecated
pub extend Usage with Eq::{equal, not_equal}

///|
#deprecated
pub extend Usage with @debug.Debug::{to_repr}
