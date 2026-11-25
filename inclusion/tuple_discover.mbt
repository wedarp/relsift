///|
#derive(Eq, @debug.Debug)
pub(all) struct TupleOptions {
  max_width : Int32
  target_unique_only : Bool
  max_cached_projections : Int32
}

///|
pub fn tuple_defaults() -> TupleOptions {
  { max_width: 2, target_unique_only: false, max_cached_projections: 128, }
}

///|
#derive(Eq, @debug.Debug)
pub(all) struct TupleInd {
  source_table : String
  source_columns : Array[String]
  target_table : String
  target_columns : Array[String]
  source_distinct : Int32
  target_distinct : Int32
  target_unique : Bool
}

///|
#derive(Eq, @debug.Debug)
pub(all) struct TupleReport {
  null_policy : @model.NullPolicy?
  status : @budget.Status
  options : TupleOptions
  limits : @budget.Limits
  usage : @budget.Usage
  cached_projections : Int32
  projections_built : Int64
  projection_pruned : Int32
  tuple_checks : Int32
  relations : Array[TupleInd]
}

///|
pub fn validate_tuple_options(
  options : TupleOptions,
) -> Unit raise @model.InputError {
  if options.max_width < 2 || options.max_cached_projections < 0 {
    raise @model.Invalid(
      "tuple discovery requires width >= 2 and a nonnegative cache limit",
    )
  }
}

///|
/// Discover every directed distinct-column mapping of widths 2 through max_width.
pub fn discover_tuples(
  tables : Array[@model.Table],
  options~ : TupleOptions = tuple_defaults(),
  limits~ : @budget.Limits = @budget.defaults(),
) -> TupleReport raise @model.InputError {
  validate_tuple_options(options)
  let meter = @budget.meter(limits)
  let ordered = ordered_tables(tables)
  let search : TupleSearch = {
    meter,
    options,
    relations: [],
    cached: 0,
    built: 0L,
    pruned: 0,
    checked: 0,
  }
  let status = try {
    let eligible = ordered.filter(t => t.column_count() >= 2)
    if eligible.length() >= 2 {
      let catalog = search.encode(eligible)
      for from, source in catalog {
        for to, target in catalog {
          meter.charge(1L)
          if from != to {
            search.search_pair(source, target)
          }
        }
      }
    }
    @budget.CompleteInDomain
  } catch {
    @budget.Exhausted(reason) => @budget.Partial(reason)
  }
  {
    null_policy: if ordered.is_empty() {
      None
    } else {
      Some(ordered[0].policy)
    },
    status,
    options,
    limits,
    usage: meter.usage(),
    cached_projections: search.cached,
    projections_built: search.built,
    projection_pruned: search.pruned,
    tuple_checks: search.checked,
    relations: search.relations,
  }
}

///|
pub extend TupleOptions with Eq::{equal, not_equal}

///|
pub extend TupleOptions with @debug.Debug::{to_repr}

///|
pub extend TupleInd with Eq::{equal, not_equal}

///|
pub extend TupleInd with @debug.Debug::{to_repr}

///|
pub extend TupleReport with Eq::{equal, not_equal}

///|
pub extend TupleReport with @debug.Debug::{to_repr}
