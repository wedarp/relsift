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
