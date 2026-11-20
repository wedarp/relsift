///|
test "strict CSV accepts quoted delimiters and newlines without repairs" {
  let t = parse_csv(
    "\uFEFFa,b\r\n\"a,b\",\"line1\nline2\"\r\n\"a\"\"b\",\r\n", "t",
  )
  assert_eq(t.rows()[0].cells, [Some("a,b"), Some("line1\nline2")])
  assert_eq(t.rows()[1].cells, [Some("a\"b"), Some("")])
  assert_eq(parse_csv("a,b\n", "t").row_count(), 0)
  assert_eq(parse_csv("a\n\n", "t").row_count(), 1)
  for
    bad in [
      "", "a,a\n1,2", "a,b\n1", "a\n\"x", "a\nx\"y", "a\n\"x\"y", "a\r1", "a,b\n1,2,3",
      ",a\n1,2",
    ] {
    assert_true(
      try {
        ignore(parse_csv(bad, "t"))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "JSON input is explicit, rejects coercion and preserves NULL distinction" {
  let input = "{\"schema_version\":1,\"null_policy\":\"equal\",\"tables\":[{\"id\":\"t\",\"columns\":[{\"id\":\"c\",\"name\":\"C\"}],\"rows\":[{\"id\":\"r1\",\"cells\":[null]},{\"id\":\"r2\",\"cells\":[\"\"]}]}]}"
  let tables = parse_tables(input)
  let probe = validate(
    tables, "{\"kind\":\"fd\",\"table\":\"t\",\"lhs\":[],\"rhs\":\"c\"}",
  )
  assert_eq(object(probe).length(), 4)
  let probe_keys : Array[String] = object(probe).keys().collect()
  probe_keys.sort_by((a, b) => a.lexical_compare(b))
  assert_eq(probe_keys, ["counterexample", "holds", "schema_version", "status"])
  assert_true(@verify.unique(tables[0], ["c"]).holds)
  assert_eq(
    canonical(
      validate(
        tables, "{\"kind\":\"fd\",\"table\":\"t\",\"lhs\":[],\"rhs\":\"c\"}",
      ),
    ),
    "{\"counterexample\":{\"first\":\"r1\",\"second\":\"r2\"},\"holds\":false,\"schema_version\":1,\"status\":{\"kind\":\"validated\"}}",
  )
  for
    bad in [
      replace_input(input, "\"equal\"", "\"reject\""),
      replace_input(input, "[null]", "[1]"),
      replace_input(
        input, "\"schema_version\":1", "\"schema_version\":1,\"schema_version\":1",
      ),
      replace_input(input, "\"tables\"", "\"unknown\""),
    ] {
    assert_true(
      try {
        ignore(parse_tables(bad))
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "canonical JSON sorts recursive object keys" {
  let value : Json = {
    "z": [Json::object(Map([("b", Json::number(1.0)), ("a", Json::null())]))],
    "a": "x",
  }
  assert_eq(canonical(value), "{\"a\":\"x\",\"z\":[{\"a\":null,\"b\":1}]}")
}

///|
fn replace_input(input : String, old : String, new : String) -> String {
  input.replace(old~, new~)
}
