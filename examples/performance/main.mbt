///|
fn main raise {
  for
    (row_count, width, cardinality, duplicate_every) in [
      (1000, 4, 16, 0),
      (4000, 6, 64, 5),
      (10000, 6, 128, 5),
    ] {
    let initial_seed = 20261120U
    let mut seed = initial_seed
    fn next() -> UInt32 {
      seed = seed * 1664525U + 1013904223U
      seed
    }
    let rows : Array[@model.Row] = []
    for r in 0..<row_count {
      let cells = if duplicate_every > 0 && r > 0 && r % duplicate_every == 0 {
        rows[r - 1].cells.copy()
      } else {
        Array::makei(width, _ => {
          Some(
            "v\{((next() >> 8) % cardinality.reinterpret_as_uint()).reinterpret_as_int()}",
          )
        })
      }
      rows.push({ id: "r\{r}", cells, })
    }
    let t = @model.table(
      "synthetic",
      Array::makei(width, c => { id: "c\{c}", name: "c\{c}", }),
      rows,
    )
    let distinct_rows : Map[Array[String?], Bool] = Map([])
    let cardinalities = Array::makei(width, c => {
      let values : Map[String?, Bool] = Map([])
      for row in rows {
        values[row.cells[c]] = true
      }
      values.length()
    })
    for row in rows {
      distinct_rows[row.cells] = true
    }
    let limits = {
      ..@budget.defaults(),
      max_lhs: 3,
      max_ucc_width: 3,
      max_work: 100000000L,
    }
    ignore(@relsift.discover(t, limits~)) // warmup outside measured runs
    let times = []
    for _ in 0..<7 {
      let started = @env.now()
      let result = @relsift.discover(t, limits~)
      assert_eq(result.status, @budget.CompleteInDomain)
      times.push(@env.now() - started)
    }
    times.sort()
    let result = @relsift.discover(t, limits~)
    let report : Json = {
      "seed": initial_seed.reinterpret_as_int(),
      "rows": row_count,
      "columns": width,
      "requested_cardinality": cardinality,
      "actual_cardinalities": cardinalities,
      "duplicate_rows": row_count - distinct_rows.length(),
      "duplicate_rate": (row_count - distinct_rows.length()).to_double() /
      row_count.to_double(),
      "repetitions": 7,
      "elapsed_ms_sorted": times.map(ms => ms.to_string()),
      "median_ms": times[3].to_string(),
      "status": @codec.status(result.status),
      "max_lhs": limits.max_lhs,
      "max_ucc_width": limits.max_ucc_width,
      "fds": result.fds.length(),
      "uccs": result.uccs.length(),
      "work": result.usage.work,
      "candidates": result.usage.candidates,
    }
    println(@codec.canonical(report))
  }
}
