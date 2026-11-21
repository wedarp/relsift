///|
test "partition refinement preserves literal tuples and duplicate rows" {
  let t = @model.table(
    "t",
    ["a", "b"].map(id => { id, name: id, }),
    [
      { id: "1", cells: [Some("a|b"), Some("c")], },
      { id: "2", cells: [Some("a"), Some("b|c")], },
      { id: "3", cells: [None, Some("")], },
      { id: "4", cells: [Some(""), None], },
    ],
    policy=@model.NullAsValue,
  )
  let meter = @budget.meter(@budget.defaults())
  let idx = index(t, meter)
  for x in [[], [0], [1], [0, 1]] {
    let names = x.map(i => t.columns()[i].id)
    assert_eq(idx.unique(x), @verify.unique(t, names).holds)
    for rhs in 0..<2 {
      if !x.contains(rhs) {
        assert_eq(
          idx.fd(x, rhs),
          @verify.fd(t, names, t.columns()[rhs].id).holds,
        )
      }
    }
  }
  assert_true(idx.unique([0, 1]))
  assert_true(meter.usage().cache_hits > 0)
  let pair = idx.witness([], rhs=Some(0)).unwrap()
  assert_true(@verify.check_pair(t, [], pair, rhs=Some("a")))
}

///|
test "all binary snapshots up to three rows and columns agree with direct scans" {
  let mut snapshots = 0
  for height in 0..<=3 {
    for width in 0..<=3 {
      for bits in 0..<(1 << (height * width)) {
        let t = @model.table(
          "t",
          Array::makei(width, c => { id: "c\{c}", name: "c\{c}", }),
          Array::makei(height, r => {
            id: "r\{r}",
            cells: Array::makei(width, c => {
              Some(if (bits & (1 << (r * width + c))) == 0 { "0" } else { "1" })
            }),
          }),
        )
        let idx = index(t, @budget.meter(@budget.defaults()))
        for mask in 0..<(1 << width) {
          let x = []
          for c in 0..<width {
            if (mask & (1 << c)) != 0 {
              x.push(c)
            }
          }
          let names = x.map(c => "c\{c}")
          assert_eq(idx.unique(x), @verify.unique(t, names).holds)
          for rhs in 0..<width {
            if !x.contains(rhs) {
              let valid = idx.fd(x, rhs)
              assert_eq(valid, @verify.fd(t, names, "c\{rhs}").holds)
              if !valid {
                assert_true(
                  @verify.check_pair(
                    t,
                    names,
                    idx.witness(x, rhs=Some(rhs)).unwrap(),
                    rhs=Some("c\{rhs}"),
                  ),
                )
              }
            }
          }
        }
        snapshots += 1
      }
    }
  }
  assert_eq(snapshots, 689)
}

///|
fn witness_fixture() -> @model.Table raise {
  @model.table("t", ["a", "b", "constant"].map(id => { id, name: id, }), [
    { id: "r1", cells: [Some("x"), Some("1"), Some("fixed")], },
    { id: "r2", cells: [Some("x"), Some("1"), Some("fixed")], },
    { id: "r3", cells: [Some("x"), Some("2"), Some("fixed")], },
    { id: "r4", cells: [Some("y"), Some("2"), Some("fixed")], },
  ])
}

///|
test "FD checks stop at witnesses without creating joint partitions" {
  let t = witness_fixture()
  let meter = @budget.meter(@budget.defaults())
  let idx = index(t, meter)
  let before = meter.usage().partitions
  assert_true(!idx.fd([0], 1))
  assert_eq(meter.usage().partitions, before)
  let work = meter.usage().work
  let pair = idx.witness([0], rhs=Some(1)).unwrap()
  assert_eq(meter.usage().work - work, 2L)
  assert_eq(pair, @verify.Pair::{ first: "r1", second: "r3", })
  assert_true(@verify.check_pair(t, ["a"], pair, rhs=Some("b")))
  assert_true(idx.fd([0], 2))
  let constant_work = meter.usage().work
  assert_true(idx.witness([0], rhs=Some(2)) is None)
  assert_eq(meter.usage().work - constant_work, 2L)
}

///|
test "witness cache owns tuple keys and separates RHS and unique queries" {
  let t = witness_fixture()
  let idx = index(t, @budget.meter(@budget.defaults()))
  let columns = [0]
  let fd = idx.witness(columns, rhs=Some(1))
  columns.push(1)
  assert_eq(idx.witness([0], rhs=Some(1)), fd)
  let collision = idx.witness([0]).unwrap()
  assert_eq(collision, @verify.Pair::{ first: "r1", second: "r2", })
  assert_true(idx.witness([], rhs=Some(2)) is None)
  assert_true(idx.witness([], rhs=Some(0)) is Some(_))
  assert_true(idx.witness([]) is Some(_))
  assert_eq(idx.witness([0], rhs=Some(1)), fd)
}

///|
test "interrupted scans never cache an unproved absence" {
  let t = witness_fixture()
  let mut interruptions = 0
  let mut completions = 0
  for work in 40..<75 {
    let meter = @budget.meter({
      ..@budget.defaults(),
      max_work: work.to_int64(),
    })
    let idx = index(t, meter)
    let finished = try {
      assert_true(idx.witness([0, 1], rhs=Some(2)) is None)
      true
    } catch {
      @budget.Exhausted(_) => false
      error => raise error
    }
    if finished {
      completions += 1
      assert_true(idx.witnesses.contains(([0, 1], Some(2))))
    } else {
      interruptions += 1
      assert_true(!idx.witnesses.contains(([0, 1], Some(2))))
    }
    assert_true(meter.usage().work <= work.to_int64())
  }
  assert_true(interruptions > 0 && completions > 0)
}
