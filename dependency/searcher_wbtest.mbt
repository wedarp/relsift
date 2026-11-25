///|
test "RHS-indexed pruning preserves results and witnesses on a dense FD catalog" {
  let width = 10
  let table = @model.table(
    "dense",
    Array::makei(width, c => { id: "c\{c}", name: "c\{c}", }),
    Array::makei(3, r => {
      id: "r\{r}",
      cells: Array::makei(width, c => Some("\{r}/\{c}")),
    }),
  )
  let limits = { ..@budget.defaults(), max_lhs: 3, }
  let reference_meter = @budget.meter(limits)
  let reference_index = @partition.index(table, reference_meter)
  let reference = []
  for size in 0..<=limits.max_lhs {
    @budget.combinations(width, size, reference_meter, fn(lhs) raise {
      for rhs in 0..<width {
        if !lhs.contains(rhs) {
          consider(reference_index, lhs, rhs, reference)
        }
      }
    })
  }
  let optimized_meter = @budget.meter(limits)
  let optimized = []
  discover(@partition.index(table, optimized_meter), optimized)
  assert_eq(optimized, reference)
  assert_eq(optimized.length(), width * (width - 1))
  assert_eq(
    optimized_meter.usage().candidates,
    reference_meter.usage().candidates,
  )
  assert_true(optimized_meter.usage().work < reference_meter.usage().work)
}
