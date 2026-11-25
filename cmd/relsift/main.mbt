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
  let options = parse_options(args)
  let command = options.command
  let path = options.path
  let rule_path = options.rule_path
  let format = options.format
  let table_id = options.table_id
  let limits = options.limits
  let step_candidates = options.step_candidates
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
      if format == "text" {
        println(@codec.explain_regression(report))
      }
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
      if format == "text" {
        println(@codec.explain_recheck(report))
      }
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
    "tuple-ind" => {
      let result = @inclusion.discover_tuples(
        tables,
        options=options.tuple_options,
        limits~,
      )
      if format == "text" {
        println(@codec.explain_tuple_discovery(result))
      } else {
        println(@codec.canonical(@codec.tuple_discovery(result)))
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
      if format == "text" {
        println(@codec.explain_diagnosis(report))
      }
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
