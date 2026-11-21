///|
fn main raise {
  let t = @codec.parse_csv("a,b\nx,1\nx,2\ny,1\ny,2\n", "export")
  let s = @engine.session(t)
  while s.progress() is @engine.Running {
    ignore(s.step(2))
    let interim = s.snapshot()
    println(
      "candidates=\{interim.usage.candidates}, proved_fds=\{interim.fds.length()}, proved_uccs=\{interim.uccs.length()}",
    )
  }
  let result = s.snapshot()
  assert_true(result.fd_complete && result.ucc_complete)
  assert_eq(result.uccs.length(), 1)
  for rule in result.uccs {
    assert_true(@engine.verify_ucc(t, rule))
  }
  let envelope : Json = {
    "schema_version": 1,
    "status": @codec.status(result.status),
    "tables": [@codec.discovery(result)],
  }
  let parsed = @codec.parse_discovery_report(@codec.canonical(envelope))
  let checked = @codec.recheck_report([t], parsed)
  assert_eq(@codec.field(@codec.object(checked), "valid"), Json::boolean(true))
  println(@codec.canonical(checked))
}
