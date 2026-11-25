///|
pub fn tuple_discovery(value : @inclusion.TupleReport) -> Json {
  let null_policy = match value.null_policy {
    Some(p) => Json::string(policy(p))
    None => Json::null()
  }
  let relations : Array[Json] = value.relations.map(r => {
    "source_table": r.source_table,
    "source_columns": r.source_columns,
    "target_table": r.target_table,
    "target_columns": r.target_columns,
    "source_distinct": r.source_distinct,
    "target_distinct": r.target_distinct,
    "target_unique": r.target_unique,
  })
  let tuple_options : Json = {
    "max_width": value.options.max_width,
    "target_unique_only": value.options.target_unique_only,
    "max_cached_projections": value.options.max_cached_projections,
  }
  {
    "schema_version": 1,
    "kind": "tuple_ind_discovery",
    "null_policy": null_policy,
    "status": status(value.status),
    "options": tuple_options,
    "limits": limits(value.limits),
    "usage": usage(value.usage),
    "cached_projections": value.cached_projections,
    "projections_built": value.projections_built,
    "projection_pruned": value.projection_pruned,
    "tuple_checks": value.tuple_checks,
    "relations": relations,
  }
}

///|
pub fn explain_tuple_discovery(value : @inclusion.TupleReport) -> String {
  let out = StringBuilder()
  out.write_string("状态：" + canonical(status(value.status)) + "\n")
  out.write_string(
    "宽度 2–\{value.options.max_width}，发现多列包含候选 \{value.relations.length()} 条。\n",
  )
  for relation in value.relations {
    let from = relation.source_columns.join(", ")
    let to = relation.target_columns.join(", ")
    out.write_string(
      "\{relation.source_table}[\{from}] ⊆ \{relation.target_table}[\{to}]，不同元组 \{relation.source_distinct} / \{relation.target_distinct}，目标唯一：\{relation.target_unique}\n",
    )
  }
  if value.status is @budget.Partial(_) {
    out.write_string(
      "预算耗尽，当前结果可能遗漏其他成立的映射。\n",
    )
  }
  out.write_string(
    "包含是当前快照的关联候选，外键仍需人工确认。",
  )
  out.to_string()
}
