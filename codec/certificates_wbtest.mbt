///|
fn certificate_fixture() -> @model.Table raise {
  parse_csv("a,b\nx,1\nx,2\ny,1\ny,2\n", "t")
}

///|
fn envelope(t : @engine.Discovery) -> Json {
  { "schema_version": 1, "status": status(t.status), "tables": [discovery(t)] }
}

///|
test "report round trip and all deletion certificates are independently checked" {
  let t = certificate_fixture()
  let d = @engine.discover(t)
  let parsed = parse_discovery_report(canonical(envelope(d)))
  assert_eq(parsed.tables[0], d)
  let checked = object(recheck_report([t], parsed))
  assert_eq(field(checked, "valid"), Json::boolean(true))
  assert_eq(field(checked, "completeness_verified"), Json::boolean(false))
  let k = d.uccs[0]
  let bad : @unique.Ucc = {
    ..k,
    deletions: [
      { removed: k.columns[0], pair: { first: "r1", second: "r1", }, },
    ],
  }
  let altered = { ..d, uccs: [bad], }
  let report = parse_discovery_report(canonical(envelope(altered)))
  assert_eq(
    field(object(recheck_report([t], report)), "valid"),
    Json::boolean(false),
  )
}

///|
test "metadata, missing tables, unknown columns, duplicate rules and widths fail" {
  let t = certificate_fixture()
  let d = @engine.discover(t)
  let changed : Array[@engine.Discovery] = [
    { ..d, row_count: 99, },
    { ..d, degenerate: true, },
    { ..d, uccs: [{ ..d.uccs[0], columns: ["missing"], }], },
    { ..d, uccs: [d.uccs[0], d.uccs[0]], usage: { ..d.usage, results: 2, }, },
    { ..d, limits: { ..d.limits, max_ucc_width: 0, }, },
  ]
  for c in changed {
    let report = parse_discovery_report(canonical(envelope(c)))
    assert_eq(
      field(object(recheck_report([t], report)), "valid"),
      Json::boolean(false),
    )
  }
  let absent = parse_discovery_report(
    "{\"schema_version\":1,\"status\":{\"kind\":\"complete_in_domain\"},\"tables\":[]}",
  )
  assert_eq(
    field(object(recheck_report([t], absent)), "valid"),
    Json::boolean(false),
  )
}

///|
test "strict certificate parsing rejects schema and counter tampering" {
  let d = @engine.discover(certificate_fixture())
  let original = canonical(envelope(d))
  let malformed = [
    original.replace(old="\"schema_version\":1", new="\"schema_version\":2"),
    original.replace(
      old="\"minimality\":\"proven\"",
      new="\"minimality\":\"assumed\"",
    ),
    original.replace(old="\"fd_complete\":true", new="\"fd_complete\":false"),
    original.replace(old="\"work\":\"", new="\"work\":\"0"),
    original.replace(old="\"results\":1", new="\"results\":0"),
    original.replace(old="\"first\":", new="\"extra\":0,\"first\":"),
  ]
  for text in malformed {
    let rejected = try {
      ignore(parse_discovery_report(text))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "all report integer fields reject fractions without truncation" {
  let d = @engine.discover(certificate_fixture())
  let original = canonical(envelope(d))
  for
    key in [
      "row_count", "column_count", "max_lhs", "max_ucc_width", "max_candidates",
      "max_results", "results", "candidates",
    ] {
    let root = object(parse_json(original))
    let record = object(array(field(root, "tables"))[0])
    let container = if key.has_prefix("max_") {
      object(field(record, "limits"))
    } else if key == "candidates" || key == "results" {
      object(field(record, "usage"))
    } else {
      record
    }
    for fraction in [-0.5, 0.5, 1.75] {
      container[key] = Json::number(fraction)
      let rejected = try {
        ignore(parse_discovery_report(canonical(Json::object(root))))
        false
      } catch {
        _ => true
      }
      assert_true(rejected)
    }
  }
  assert_eq(natural(parse_json("1.0")), 1)
  assert_eq(natural(parse_json("1e2")), 100)
}

///|
test "orphan summary limits use the same exact integer contract" {
  let t = certificate_fixture()
  for fraction in ["0.5", "-0.5", "1.75"] {
    let request = "{\"kind\":\"ind\",\"source_table\":\"t\",\"source_column\":\"a\",\"target_table\":\"t\",\"target_column\":\"b\",\"orphan_limit\":" +
      fraction +
      "}"
    let validation_rejected = try {
      ignore(validate([t], request))
      false
    } catch {
      _ => true
    }
    let diagnosis_rejected = try {
      ignore(diagnose([t], request))
      false
    } catch {
      _ => true
    }
    assert_true(validation_rejected && diagnosis_rejected)
  }
}

///|
test "partial, empty and nullable certificates retain their meaning" {
  let nullable = @model.table(
    "n",
    [{ id: "c", name: "c", }],
    [{ id: "n", cells: [None], }, { id: "s", cells: [Some("")], }],
    policy=@model.NullAsValue,
  )
  let nullable_report = parse_discovery_report(
    canonical(envelope(@engine.discover(nullable))),
  )
  assert_eq(
    field(object(recheck_report([nullable], nullable_report)), "valid"),
    Json::boolean(true),
  )
  let t = parse_csv("c\n", "t")
  let d = @engine.discover(t)
  let checked_empty = object(
    recheck_report([t], parse_discovery_report(canonical(envelope(d)))),
  )
  assert_eq(field(checked_empty, "valid"), Json::boolean(true))
  let partial = @engine.discover(certificate_fixture(), limits={
    ..@budget.defaults(),
    max_results: 0,
  })
  let checked = object(
    recheck_report(
      [certificate_fixture()],
      parse_discovery_report(canonical(envelope(partial))),
    ),
  )
  assert_eq(field(checked, "valid"), Json::boolean(true))
  assert_eq(
    field(object(field(checked, "reported_status")), "kind"),
    Json::string("partial"),
  )
}
