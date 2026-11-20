///|
/// Sort every JSON object's keys. Arrays retain their documented deterministic order.
pub fn canonical(value : Json) -> String {
  match value {
    Object(m) => {
      let keys : Array[String] = m.keys().collect()
      keys.sort_by((a, b) => a.lexical_compare(b))
      let out = StringBuilder()
      out.write_string("{")
      for i, key in keys {
        if i > 0 {
          out.write_string(",")
        }
        out.write_string(Json::string(key).stringify())
        out.write_string(":")
        out.write_string(canonical(m[key]))
      }
      out.write_string("}")
      out.to_string()
    }
    Array(a) => "[" + a.map(canonical).join(",") + "]"
    _ => value.stringify()
  }
}

///|
pub fn status(value : @budget.Status) -> Json {
  match value {
    CompleteInDomain => { "kind": "complete_in_domain" }
    Partial(reason) => { "kind": "partial", "reason": reason }
  }
}

///|
pub fn policy(value : @model.NullPolicy) -> String {
  match value {
    RejectNull => "reject"
    NullAsValue => "equal"
  }
}

///|
fn usage(value : @budget.Usage) -> Json {
  {
    "candidates": value.candidates,
    "work": value.work,
    "results": value.results,
    "partitions": value.partitions,
    "cache_hits": value.cache_hits,
  }
}

///|
fn limits(value : @budget.Limits) -> Json {
  {
    "max_lhs": value.max_lhs,
    "max_ucc_width": value.max_ucc_width,
    "max_candidates": value.max_candidates,
    "max_work": value.max_work,
    "max_results": value.max_results,
  }
}

///|
fn pair(value : @verify.Pair) -> Json {
  { "first": value.first, "second": value.second }
}

///|
pub fn discovery(value : @engine.Discovery) -> Json {
  let fds : Array[Json] = value.fds.map(f => {
    let deletions : Array[Json] = f.deletions.map(d => {
      "removed": d.removed,
      "pair": pair(d.pair),
    })
    {
      "lhs": f.lhs,
      "rhs": f.rhs,
      "minimality": "proven",
      "deletions": deletions,
    }
  })
  let uccs : Array[Json] = value.uccs.map(k => {
    let deletions : Array[Json] = k.deletions.map(d => {
      "removed": d.removed,
      "pair": pair(d.pair),
    })
    { "columns": k.columns, "minimality": "proven", "deletions": deletions }
  })
  {
    "table_id": value.table_id,
    "row_count": value.row_count,
    "column_count": value.column_count,
    "null_policy": policy(value.null_policy),
    "status": status(value.status),
    "fd_complete": value.fd_complete,
    "ucc_complete": value.ucc_complete,
    "limits": limits(value.limits),
    "usage": usage(value.usage),
    "degenerate": value.degenerate,
    "fds": fds,
    "uccs": uccs,
  }
}

///|
pub fn inclusion(value : @inclusion.Report) -> Json {
  let null_policy = match value.null_policy {
    Some(p) => Json::string(policy(p))
    None => Json::null()
  }
  let relations : Array[Json] = value.relations.map(r => {
    "source_table": r.source_table,
    "source_column": r.source_column,
    "target_table": r.target_table,
    "target_column": r.target_column,
    "source_distinct": r.source_distinct,
    "target_distinct": r.target_distinct,
    "target_unique": r.target_unique,
  })
  {
    "schema_version": 1,
    "null_policy": null_policy,
    "status": status(value.status),
    "limits": limits(value.limits),
    "usage": usage(value.usage),
    "relations": relations,
  }
}

///|
pub fn verdict(value : @verify.Verdict) -> Json {
  let example = match value.counterexample {
    Some(p) => pair(p)
    None => Json::null()
  }
  {
    "schema_version": 1,
    "status": { "kind": "validated" },
    "holds": value.holds,
    "counterexample": example,
  }
}

///|
pub fn inclusion_verdict(value : @verify.InclusionVerdict) -> Json {
  let orphans = value.orphans.map(cell => {
    match cell {
      Some(s) => Json::string(s)
      None => Json::null()
    }
  })
  {
    "schema_version": 1,
    "status": { "kind": "validated" },
    "holds": value.holds,
    "source_distinct": value.source_distinct,
    "target_distinct": value.target_distinct,
    "target_unique": value.target_unique,
    "orphan_count": value.orphan_count,
    "orphans": orphans,
    "orphans_omitted": value.orphans_omitted,
  }
}

///|
pub fn explain(value : @engine.Discovery) -> String {
  let out = StringBuilder()
  out.write_string(
    "表 \{value.table_id}：\{value.row_count} 行，\{value.column_count} 列\n",
  )
  out.write_string("状态：" + canonical(status(value.status)) + "\n")
  for f in value.fds {
    out.write_string("FD {" + f.lhs.join(", ") + "} -> " + f.rhs + "\n")
  }
  for k in value.uccs {
    out.write_string("唯一组合 {" + k.columns.join(", ") + "}\n")
  }
  if value.degenerate {
    out.write_string(
      "输入退化：空表/单行表按数学定义输出，需谨慎解释。\n",
    )
  }
  out.write_string(
    "规律仅适用于当前快照，需要人工确认业务约束。\n",
  )
  out.to_string()
}
