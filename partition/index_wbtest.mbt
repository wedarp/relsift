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
