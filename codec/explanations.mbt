///|
fn status_text(value : Json) -> String raise {
  match parse_status(value) {
    CompleteInDomain => "声明域内完成"
    Partial(reason) => "部分结果（" + reason + "）"
  }
}

///|
fn holds_text(value : Json) -> String raise @model.InputError {
  if value == Json::boolean(true) {
    "约束成立"
  } else if value == Json::boolean(false) {
    "已找到反例"
  } else if value == Json::null() {
    "尚未判定"
  } else {
    raise @model.Invalid("expected nullable holds state")
  }
}

///|
/// Compact summary of a diagnosis produced by this package; JSON retains details.
pub fn explain_diagnosis(value : Json) -> String raise {
  let m = object(value)
  let conclusion = holds_text(field(m, "holds"))
  let counts = if boolean(field(m, "counts_complete")) {
    "计数完整"
  } else {
    "计数仅为下界"
  }
  let detail = match string(field(m, "kind")) {
    "fd_diagnosis" =>
      "FD 诊断：\{conclusion}；冲突组 \{natural(field(m, "conflicting_groups"))}，违反行对 \{string(field(m, "violating_pairs"))}。"
    "unique_diagnosis" =>
      "唯一组合诊断：\{conclusion}；碰撞组 \{natural(field(m, "collision_groups"))}，碰撞行对 \{string(field(m, "collision_pairs"))}，超额记录 \{natural(field(m, "excess_rows"))}。"
    "ind_diagnosis" => {
      let target = field(m, "target_unique")
      let unique_text = if target == Json::null() {
        "尚未判定"
      } else if boolean(target) {
        "是"
      } else {
        "否"
      }
      "包含诊断：\{conclusion}；孤儿值 \{natural(field(m, "orphan_values"))}，孤儿记录 \{natural(field(m, "orphan_rows"))}；目标唯一：\{unique_text}。"
    }
    _ => raise @model.Invalid("expected diagnosis report")
  }
  detail +
  "\n" +
  counts +
  "；状态：" +
  status_text(field(m, "status")) +
  "。\n"
}

///|
pub fn explain_recheck(value : Json) -> String raise {
  let m = object(value)
  let verdict = if boolean(field(m, "valid")) {
    "所列规则与证据有效"
  } else {
    "存在无效记录"
  }
  "证据复核：FD \{natural(field(m, "checked_fds"))} 条，唯一组合 \{natural(field(m, "checked_uccs"))} 个，问题 \{array(field(m, "issues")).length()} 项；\{verdict}。\n原报告状态：" +
  status_text(field(m, "reported_status")) +
  "。未验证搜索完整性。\n"
}

///|
pub fn explain_regression(value : Json) -> String raise {
  let root = object(value)
  let out = StringBuilder()
  out.write_string(
    "快照回归：" + status_text(field(root, "status")) + "。\n",
  )
  for value in array(field(root, "tables")) {
    let t = object(value)
    let mut minimal = 0
    let mut nonminimal = 0
    let mut violated = 0
    let mut missing = 0
    for check in array(field(t, "checks")) {
      let outcome = object(field(object(check), "outcome"))
      match string(field(outcome, "kind")) {
        "held_minimal" => minimal += 1
        "held_nonminimal" => nonminimal += 1
        "violated" => violated += 1
        "missing_columns" => missing += 1
        _ => raise @model.Invalid("unknown regression outcome")
      }
    }
    out.write_string(
      "表 " +
      canonical(field(t, "table_id")) +
      "：已检查 \{natural(field(t, "checked_rules"))}/\{string(field(t, "baseline_rules"))} 条；仍最小 \{minimal}，不再最小 \{nonminimal}，反例 \{violated}，缺列 \{missing}。\n",
    )
  }
  out.write_string(
    "基线状态：" +
    status_text(field(root, "baseline_status")) +
    "。仅复核所列基线规则，未搜索新增关系。\n",
  )
  let untracked = strings(field(root, "untracked_tables"))
  if !untracked.is_empty() {
    out.write_string(
      "未纳入基线的表：" +
      canonical(field(root, "untracked_tables")) +
      "。\n",
    )
  }
  out.to_string()
}
