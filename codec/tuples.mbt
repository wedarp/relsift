///|
fn tuple_inclusion_json(value : @verify.TupleInclusion) -> Json {
  let orphans : Array[Json] = value.orphans.map(o => {
    "values": cells_json(o.values),
    "first_source_row": o.first_source_row,
    "source_count": o.source_count,
  })
  {
    "schema_version": 1,
    "kind": "tuple_ind_diagnosis",
    "source_table": value.source_table,
    "target_table": value.target_table,
    "source_columns": value.source_columns,
    "target_columns": value.target_columns,
    "status": status(value.status),
    "holds": nullable_bool(value.holds),
    "target_unique": nullable_bool(value.target_unique),
    "counts_complete": value.status is @budget.CompleteInDomain,
    "source_rows_checked": value.source_rows_checked,
    "source_distinct": value.source_distinct,
    "target_distinct": match value.target_distinct {
      Some(n) => Json::number(n.to_double())
      None => Json::null()
    },
    "orphan_tuples": value.orphan_tuples,
    "orphan_rows": value.orphan_rows,
    "orphans_omitted": value.orphan_tuples - value.orphans.length(),
    "orphans": orphans,
    "usage": usage(value.usage),
  }
}

///|
fn diagnose_tuple_request(
  tables : Array[@model.Table],
  rule : Map[String, Json],
  limits : @budget.Limits,
) -> Json raise {
  only(rule, [
    "kind", "source_table", "source_columns", "target_table", "target_columns", "orphan_limit",
  ])
  let orphan_limit = match rule.get("orphan_limit") {
    Some(value) => natural(value)
    None => 10
  }
  tuple_inclusion_json(
    @verify.tuple_inclusion(
      find_table(tables, string(field(rule, "source_table"))),
      strings(field(rule, "source_columns")),
      find_table(tables, string(field(rule, "target_table"))),
      strings(field(rule, "target_columns")),
      orphan_limit~,
      limits~,
    ),
  )
}
