///|
fn nullable_bool(value : Bool?) -> Json {
  match value {
    Some(v) => Json::boolean(v)
    None => Json::null()
  }
}

///|
fn cells_json(values : Array[String?]) -> Array[Json] {
  values.map(v => {
    match v {
      Some(s) => Json::string(s)
      None => Json::null()
    }
  })
}

///|
pub fn fd_diagnosis(value : @verify.FdDiagnosis) -> Json {
  let groups : Array[Json] = value.groups.map(g => {
    "determinant": cells_json(g.determinant),
    "rows": g.rows,
    "distinct_rhs": g.distinct_rhs,
    "violating_pairs": g.violating_pairs,
    "witness": pair(g.witness),
  })
  {
    "schema_version": 1,
    "kind": "fd_diagnosis",
    "lhs": value.lhs,
    "rhs": value.rhs,
    "status": status(value.status),
    "holds": nullable_bool(value.holds),
    "counts_complete": value.status == @budget.CompleteInDomain,
    "conflicting_groups": value.conflicting_groups,
    "violating_pairs": value.violating_pairs,
    "groups": groups,
    "usage": usage(value.usage),
  }
}

///|
pub fn unique_diagnosis(value : @verify.UniqueDiagnosis) -> Json {
  let groups : Array[Json] = value.groups.map(g => {
    "values": cells_json(g.values),
    "rows": g.rows,
    "collision_pairs": g.collision_pairs,
  })
  {
    "schema_version": 1,
    "kind": "unique_diagnosis",
    "columns": value.columns,
    "status": status(value.status),
    "holds": nullable_bool(value.holds),
    "counts_complete": value.status == @budget.CompleteInDomain,
    "collision_groups": value.collision_groups,
    "excess_rows": value.excess_rows,
    "collision_pairs": value.collision_pairs,
    "groups": groups,
    "usage": usage(value.usage),
  }
}

///|
pub fn inclusion_diagnosis(value : @verify.InclusionDiagnosis) -> Json {
  let groups : Array[Json] = value.groups.map(g => {
    "value": match g.value {
      Some(s) => Json::string(s)
      None => Json::null()
    },
    "source_rows": g.source_rows,
  })
  {
    "schema_version": 1,
    "kind": "ind_diagnosis",
    "status": status(value.status),
    "holds": nullable_bool(value.holds),
    "target_unique": nullable_bool(value.target_unique),
    "counts_complete": value.status == @budget.CompleteInDomain,
    "orphan_values": value.orphan_values,
    "orphan_rows": value.orphan_rows,
    "groups": groups,
    "usage": usage(value.usage),
  }
}

///|
pub fn diagnose(
  tables : Array[@model.Table],
  request : String,
  limits~ : @budget.Limits = @budget.defaults(),
) -> Json raise {
  let rule = object(parse_json(request))
  match string(field(rule, "kind")) {
    "tuple_ind" => diagnose_tuple_request(tables, rule, limits)
    "fd" => {
      only(rule, ["kind", "table", "lhs", "rhs"])
      fd_diagnosis(
        @verify.diagnose_fd(
          find_table(tables, string(field(rule, "table"))),
          strings(field(rule, "lhs")),
          string(field(rule, "rhs")),
          limits~,
        ),
      )
    }
    "unique" => {
      only(rule, ["kind", "table", "columns"])
      unique_diagnosis(
        @verify.diagnose_unique(
          find_table(tables, string(field(rule, "table"))),
          strings(field(rule, "columns")),
          limits~,
        ),
      )
    }
    "ind" => {
      only(rule, [
        "kind", "source_table", "source_column", "target_table", "target_column",
        "orphan_limit",
      ])
      let effective = match rule.get("orphan_limit") {
        Some(v) => {
          let limit = natural(v)
          { ..limits, max_results: Int32::min(limits.max_results, limit), }
        }
        None => limits
      }
      inclusion_diagnosis(
        @verify.diagnose_inclusion(
          find_table(tables, string(field(rule, "source_table"))),
          string(field(rule, "source_column")),
          find_table(tables, string(field(rule, "target_table"))),
          string(field(rule, "target_column")),
          limits=effective,
        ),
      )
    }
    _ => raise @model.Invalid("unknown constraint kind")
  }
}
