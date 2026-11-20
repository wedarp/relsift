///|
test "budget boundary accounting never exceeds declared maxima" {
  let m = meter({
    ..defaults(),
    max_candidates: 1,
    max_work: 2L,
    max_results: 0,
  })
  m.candidate()
  m.charge(1L)
  assert_true(
    try {
      m.charge(1L)
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      m.candidate()
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      m.result()
      false
    } catch {
      _ => true
    },
  )
  assert_eq(m.usage().work, 2L)
  assert_eq(m.usage().candidates, 1)
  assert_eq(m.usage().results, 0)
}
