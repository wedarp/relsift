///|
fn find_table(
  tables : Array[@model.Table],
  id : String,
) -> @model.Table raise @model.InputError {
  for t in tables {
    if t.id == id {
      return t
    }
  }
  raise @model.Invalid("unknown table ID: " + id)
}

///|
fn strings(value : Json) -> Array[String] raise @model.InputError {
  array(value).map(string)
}

///|
/// Evaluate one explicitly requested constraint using only the independent validators.
pub fn validate(tables : Array[@model.Table], request : String) -> Json raise {
  let rule = object(parse_json(request))
  let kind = string(field(rule, "kind"))
  match kind {
    "fd" => {
      only(rule, ["kind", "table", "lhs", "rhs"])
      verdict(
        @verify.fd(
          find_table(tables, string(field(rule, "table"))),
          strings(field(rule, "lhs")),
          string(field(rule, "rhs")),
        ),
      )
    }
    "unique" => {
      only(rule, ["kind", "table", "columns"])
      verdict(
        @verify.unique(
          find_table(tables, string(field(rule, "table"))),
          strings(field(rule, "columns")),
        ),
      )
    }
    "ind" => {
      only(rule, [
        "kind", "source_table", "source_column", "target_table", "target_column",
        "orphan_limit",
      ])
      let orphan_limit : Int32 = match rule.get("orphan_limit") {
        Some(v) => @json.from_json(v)
        None => 10
      }
      inclusion_verdict(
        @verify.inclusion(
          find_table(tables, string(field(rule, "source_table"))),
          string(field(rule, "source_column")),
          find_table(tables, string(field(rule, "target_table"))),
          string(field(rule, "target_column")),
          orphan_limit~,
        ),
      )
    }
    _ => raise @model.Invalid("unknown constraint kind")
  }
}
