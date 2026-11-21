///|
async fn read_input(path : String) -> String {
  if @fs.file_size(path) > 8388608L {
    raise @model.Invalid("file exceeds 8 MiB")
  }
  let bytes = @fs.read_binary(path)
  if bytes.length() > 8388608 {
    raise @model.Invalid("file exceeds 8 MiB")
  }
  @utf8.decode(bytes, ignore_bom=true)
}

///|
async fn execute(args : Array[String]) -> Int32 {
  if args.length() < 3 {
    raise @model.Invalid(
      "usage: relsift discover|discover-stepped|ind|verify|diagnose|verify-report|compare INPUT [RULE_OR_REPORT.json] [--format json|text] [--table-id ID] [--step-candidates N] [--max-lhs N] [--max-ucc-width N] [--max-candidates N] [--max-work N] [--max-results N]",
    )
  }
  let command = args[1]
  let path = args[2]
  let mut rule_path : String? = None
  let mut offset = 3
  if command == "verify" ||
    command == "diagnose" ||
    command == "verify-report" ||
    command == "compare" {
    if args.length() <= 3 {
      raise @model.Invalid(command + " requires RULE_OR_REPORT.json")
    }
    rule_path = Some(args[3])
    offset = 4
  }
  let mut format = "json"
  let mut table_id = "table"
  let mut limits = @budget.defaults()
  let mut step_candidates = 100
  while offset < args.length() {
    if offset + 1 >= args.length() {
      raise @model.Invalid("option requires a value")
    }
    let key = args[offset]
    let value = args[offset + 1]
    match key {
      "--format" => format = value
      "--table-id" => table_id = value
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
  if format != "json" && format != "text" {
    raise @model.Invalid("format must be json or text")
  }
  let input = read_input(path)
  let tables = if path.has_suffix(".csv") {
    [@codec.parse_csv(input, table_id)]
  } else if path.has_suffix(".json") {
    @codec.parse_tables(input)
  } else {
    raise @model.Invalid("input extension must be .csv or .json")
  }
  match command {
    "compare" => {
      let report = @codec.compare_report(
        tables,
        @codec.parse_discovery_report(read_input(rule_path.unwrap())),
        limits~,
      )
      println(@codec.canonical(report))
      let fields = @codec.object(report)
      if @codec.string(
          @codec.field(@codec.object(@codec.field(fields, "status")), "kind"),
        ) ==
        "partial" {
        3
      } else if @codec.field(fields, "has_violations") == Json::boolean(true) {
        1
      } else {
        0
      }
    }
    "verify-report" => {
      let report = @codec.recheck_report(
        tables,
        @codec.parse_discovery_report(read_input(rule_path.unwrap())),
      )
      println(@codec.canonical(report))
      if @codec.field(@codec.object(report), "valid") == Json::boolean(true) {
        0
      } else {
        1
      }
    }
    "discover" | "discover-stepped" => {
      let results = tables.map(t => {
        if command == "discover" {
          @engine.discover(t, limits~)
        } else {
          let s = @engine.session(t, limits~)
          while s.progress() is @engine.Running {
            ignore(s.step(step_candidates))
          }
          s.snapshot()
        }
      })
      let mut partial = false
      for result in results {
        if result.status is @budget.Partial(_) {
          partial = true
        }
      }
      if format == "text" {
        for result in results {
          println(@codec.explain(result))
        }
      } else {
        let report : Json = {
          "schema_version": 1,
          "status": @codec.status(
            if partial {
              @budget.Partial("table_budget")
            } else {
              @budget.CompleteInDomain
            },
          ),
          "tables": results.map(@codec.discovery),
        }
        println(@codec.canonical(report))
      }
      if partial {
        3
      } else {
        0
      }
    }
    "ind" => {
      let result = @inclusion.discover(tables, limits~)
      if format == "text" {
        println("状态：" + @codec.canonical(@codec.status(result.status)))
        for r in result.relations {
          println(
            "\{r.source_table}.\{r.source_column} ⊆ \{r.target_table}.\{r.target_column}；目标唯一：\{r.target_unique}",
          )
        }
        println("包含关系只是关联候选，需要人工确认外键。")
      } else {
        println(@codec.canonical(@codec.inclusion(result)))
      }
      if result.status is @budget.Partial(_) {
        3
      } else {
        0
      }
    }
    "verify" => {
      let report = @codec.validate(tables, read_input(rule_path.unwrap()))
      let holds = @codec.field(@codec.object(report), "holds") ==
        Json::boolean(true)
      if format == "text" {
        println(
          if holds {
            "约束在当前快照成立。"
          } else {
            "约束不成立，反例或孤儿摘要如下。"
          },
        )
      }
      println(@codec.canonical(report))
      if holds {
        0
      } else {
        1
      }
    }
    "diagnose" => {
      let report = @codec.diagnose(
        tables,
        read_input(rule_path.unwrap()),
        limits~,
      )
      println(@codec.canonical(report))
      let fields = @codec.object(report)
      let kind = @codec.string(
        @codec.field(@codec.object(@codec.field(fields, "status")), "kind"),
      )
      if kind == "partial" {
        3
      } else if @codec.field(fields, "holds") == Json::boolean(true) {
        0
      } else {
        1
      }
    }
    _ => raise @model.Invalid("unknown command: " + command)
  }
}

///|
async fn main {
  let code = execute(@env.args()) catch {
    error => {
      let message = match error {
        @model.Invalid(message) => message
        _ => error.to_string()
      }
      let report : Json = {
        "schema_version": 1,
        "status": { "kind": "failed" },
        "error": message,
      }
      println(@codec.canonical(report))
      2
    }
  }
  @env.exit(code)
}
