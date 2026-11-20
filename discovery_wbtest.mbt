///|
fn snapshot(cells : Array[Array[String?]], width : Int32) -> @model.Table raise {
  @model.table(
    "t",
    Array::makei(width, c => { id: "c\{c}", name: "c\{c}", }),
    cells.mapi((r, cells) => { id: "r\{r}", cells, }),
    policy=@model.NullAsValue,
  )
}

///|
fn signatures(result : Discovery) -> (Array[String], Array[String]) {
  let fds = result.fds.map(fd => fd.lhs.join(",") + "->" + fd.rhs)
  let uccs = result.uccs.map(ucc => ucc.columns.join(","))
  fds.sort()
  uccs.sort()
  (fds, uccs)
}

///|
/// Oracle checks *every* strict subset, without using production pruning or partitions.
fn oracle(t : @model.Table) -> (Array[String], Array[String]) raise {
  let cols = t.columns().map(c => c.id)
  let sets : Array[Array[String]] = []
  for mask in 0..<(1 << cols.length()) {
    let x = []
    for i, c in cols {
      if (mask & (1 << i)) != 0 {
        x.push(c)
      }
    }
    sets.push(x)
  }
  let fds = []
  let uccs = []
  for x in sets {
    let proper = sets.filter(y => {
      y.length() < x.length() && y.all(c => x.contains(c))
    })
    if @verify.unique(t, x).holds &&
      proper.all(y => !@verify.unique(t, y).holds) {
      uccs.push(x.join(","))
    }
    for a in cols {
      if !x.contains(a) &&
        @verify.fd(t, x, a).holds &&
        proper.all(y => !@verify.fd(t, y, a).holds) {
        fds.push(x.join(",") + "->" + a)
      }
    }
  }
  fds.sort()
  uccs.sort()
  (fds, uccs)
}

///|
fn compare_oracle(t : @model.Table) -> Unit raise {
  let result = discover(t)
  assert_eq(result.status, @budget.CompleteInDomain)
  assert_eq(signatures(result), oracle(t))
  for fd in result.fds {
    assert_true(verify_fd(t, fd))
  }
  for ucc in result.uccs {
    assert_true(verify_ucc(t, ucc))
  }
}

///|
test "complete discovery on all 689 binary snapshots" {
  for height in 0..<=3 {
    for width in 0..<=3 {
      for bits in 0..<(1 << (height * width)) {
        compare_oracle(
          snapshot(
            Array::makei(height, r => {
              Array::makei(width, c => {
                Some(
                  if (bits & (1 << (r * width + c))) == 0 {
                    "0"
                  } else {
                    "1"
                  },
                )
              })
            }),
            width,
          ),
        )
      }
    }
  }
}

///|
test "seeded multivalue differential and duplicate-row metamorphism" {
  let mut seed = 20261120U
  fn next() -> UInt32 {
    seed = seed * 1664525U + 1013904223U
    seed
  }
  let values = [
    None,
    Some(""),
    Some("01"),
    Some("1"),
    Some("A"),
    Some("a"),
    Some("é"),
    Some("é"),
    Some("x|y"),
  ]
  for _ in 0..<300 {
    let width = (next() % 5U).reinterpret_as_int()
    let height = (next() % 7U).reinterpret_as_int()
    let cells = Array::makei(height, _ => {
      Array::makei(width, _ => {
        values[(next() % values.length().reinterpret_as_uint()).reinterpret_as_int()]
      })
    })
    let t = snapshot(cells, width)
    compare_oracle(t)
    if height > 0 {
      let copies = cells.copy()
      copies.push(cells[0].copy())
      let repeated = discover(snapshot(copies, width))
      assert_eq(signatures(repeated).0, signatures(discover(t)).0)
      assert_eq(repeated.uccs.length(), 0)
    }
  }
}

///|
test "width domain, budget truncation and forged minimality evidence" {
  let t = snapshot(
    [[Some("a"), Some("x")], [Some("a"), Some("y")], [Some("b"), Some("x")]],
    2,
  )
  let bounded = discover(t, limits={
    ..@budget.defaults(),
    max_lhs: 0,
    max_ucc_width: 1,
  })
  assert_eq(bounded.status, @budget.CompleteInDomain)
  assert_eq(bounded.fds.length(), 0)
  assert_eq(bounded.uccs.length(), 0)
  for
    limits in [
      { ..@budget.defaults(), max_work: 0L, },
      { ..@budget.defaults(), max_candidates: 0, },
      { ..@budget.defaults(), max_results: 0, },
    ] {
    let result = discover(t, limits~)
    assert_true(result.status is @budget.Partial(_))
    assert_true(!result.ucc_complete)
    for fd in result.fds {
      assert_true(verify_fd(t, fd))
    }
    for ucc in result.uccs {
      assert_true(verify_ucc(t, ucc))
    }
  }
  let key = discover(t).uccs[0]
  assert_true(!verify_ucc(t, { ..key, deletions: [], }))
}

///|
test "row and column reorder, renaming and deterministic witnesses" {
  let t = snapshot(
    [[Some("x"), Some("p")], [Some("x"), Some("q")], [Some("y"), Some("p")]],
    2,
  )
  let rows = t.rows()
  rows.rev_in_place()
  let columns = t.columns()
  columns.rev_in_place()
  let permuted = @model.table(
    "t",
    columns,
    rows.map(r => {
      let cells = r.cells.copy()
      cells.rev_in_place()
      @model.Row::{ id: r.id, cells, }
    }),
    policy=@model.NullAsValue,
  )
  assert_eq(discover(t), discover(permuted))
  let renamed = @model.table(
    "t",
    t.columns().map(c => { id: "new_" + c.id, name: "label_" + c.name, }),
    t.rows(),
    policy=@model.NullAsValue,
  )
  let original = discover(t)
  let mapped_fds = original.fds.map(f => {
    (f.lhs.map(id => "new_" + id), "new_" + f.rhs)
  })
  let mapped_keys = original.uccs.map(k => k.columns.map(id => "new_" + id))
  assert_eq(mapped_fds, discover(renamed).fds.map(f => (f.lhs, f.rhs)))
  assert_eq(mapped_keys, discover(renamed).uccs.map(k => k.columns))
  for work in 0..<200 {
    let partial = discover(t, limits={
      ..@budget.defaults(),
      max_work: work.to_int64(),
    })
    for f in partial.fds {
      assert_true(verify_fd(t, f))
    }
    for k in partial.uccs {
      assert_true(verify_ucc(t, k))
    }
    assert_true(partial.usage.work <= work.to_int64())
  }
}
