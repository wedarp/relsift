///|
struct Options {
  command : String
  path : String
  rule_path : String?
  format : String
  table_id : String
  limits : @budget.Limits
  tuple_options : @inclusion.TupleOptions
  step_candidates : Int32
}

///|
/// Parse and validate the entire invocation before reading any input file.
fn parse_options(args : Array[String]) -> Options raise {
  if args.length() < 3 {
    raise @model.Invalid(
      "usage: relsift discover|discover-stepped|ind|tuple-ind|verify|diagnose|verify-report|compare INPUT [RULE_OR_REPORT.json] [--format json|text] [--table-id ID] [--step-candidates N] [--max-lhs N] [--max-ucc-width N] [--max-ind-width N] [--target-unique-only true|false] [--max-cached-projections N] [--max-candidates N] [--max-work N] [--max-results N]",
    )
  }
  let command = args[1]
  if ![
      "discover", "discover-stepped", "ind", "tuple-ind", "verify", "diagnose", "verify-report",
      "compare",
    ].contains(command) {
    raise @model.Invalid("unknown command: " + command)
  }
  let path = args[2]
  if !path.has_suffix(".csv") && !path.has_suffix(".json") {
    raise @model.Invalid("input extension must be .csv or .json")
  }
  if command == "tuple-ind" && !path.has_suffix(".json") {
    raise @model.Invalid("tuple-ind requires JSON table input")
  }
  let needs_rule = ["verify", "diagnose", "verify-report", "compare"].contains(
    command,
  )
  if needs_rule && args.length() <= 3 {
    raise @model.Invalid(command + " requires RULE_OR_REPORT.json")
  }
  let rule_path = if needs_rule { Some(args[3]) } else { None }
  let mut offset = if needs_rule { 4 } else { 3 }
  let mut format = "json"
  let mut table_id = "table"
  let mut limits = @budget.defaults()
  let mut tuple_options = @inclusion.tuple_defaults()
  let mut step_candidates = 100
  let seen = Map([])
  while offset < args.length() {
    if offset + 1 >= args.length() {
      raise @model.Invalid("option requires a value")
    }
    let key = args[offset]
    let value = args[offset + 1]
    if seen.contains(key) {
      raise @model.Invalid("duplicate option: " + key)
    }
    seen[key] = true
    if key.has_prefix("--max-") &&
      (command == "verify" || command == "verify-report") {
      raise @model.Invalid(
        command +
        " uses an unbudgeted independent validator; use diagnose for bounded single-rule checks",
      )
    }
    if (key == "--max-lhs" || key == "--max-ucc-width") &&
      command != "discover" &&
      command != "discover-stepped" {
      raise @model.Invalid("width limits only apply to discovery")
    }
    if command != "tuple-ind" &&
      ["--max-ind-width", "--target-unique-only", "--max-cached-projections"].contains(
        key,
      ) {
      raise @model.Invalid("tuple discovery option requires tuple-ind: " + key)
    }
    match key {
      "--format" => format = value
      "--table-id" => {
        if !path.has_suffix(".csv") {
          raise @model.Invalid("table ID override requires CSV input")
        }
        table_id = value
      }
      "--step-candidates" => {
        if command != "discover-stepped" {
          raise @model.Invalid("step quota requires discover-stepped")
        }
        step_candidates = @string.parse_int(value)
        if step_candidates <= 0 {
          raise @model.Invalid("CLI step quota must be positive")
        }
      }
      "--max-lhs" => limits = { ..limits, max_lhs: @string.parse_int(value), }
      "--max-ucc-width" =>
        limits = { ..limits, max_ucc_width: @string.parse_int(value), }
      "--max-ind-width" =>
        tuple_options = {
          ..tuple_options,
          max_width: @string.parse_int(value),
        }
      "--max-cached-projections" =>
        tuple_options = {
          ..tuple_options,
          max_cached_projections: @string.parse_int(value),
        }
      "--target-unique-only" => {
        if value != "true" && value != "false" {
          raise @model.Invalid("target uniqueness filter must be true or false")
        }
        tuple_options = {
          ..tuple_options,
          target_unique_only: value == "true",
        }
      }
      "--max-candidates" =>
        limits = { ..limits, max_candidates: @string.parse_int(value), }
      "--max-work" =>
        limits = { ..limits, max_work: @string.parse_int64(value), }
      "--max-results" =>
        limits = { ..limits, max_results: @string.parse_int(value), }
      _ => raise @model.Invalid("unknown option: " + key)
    }
    offset += 2
  }
  ignore(@budget.meter(limits))
  @inclusion.validate_tuple_options(tuple_options)
  if format != "json" && format != "text" {
    raise @model.Invalid("format must be json or text")
  }
  {
    command,
    path,
    rule_path,
    format,
    table_id,
    limits,
    tuple_options,
    step_candidates,
  }
}
