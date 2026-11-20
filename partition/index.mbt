///|
struct Partition {
  classes : Array[Int32]
  count : Int32
}

///|
/// Cache belongs to one owned snapshot. Integer tuple keys use both Hash and Eq.
pub struct Index {
  table : @model.Table
  priv rows : Array[@model.Row]
  priv encoded : Array[Array[Int32]]
  priv cache : Map[Array[Int32], Partition]
  meter : @budget.Meter
  priv width : Int32
}

///|
pub fn index(t : @model.Table, meter : @budget.Meter) -> Index raise {
  meter.charge(
    (t.row_count().to_int64() + 1L) * (t.column_count().to_int64() + 1L),
  )
  let rows = t.rows()
  let encoded = []
  let cache : Map[Array[Int32], Partition] = Map([])
  cache[[]] = {
    classes: Array::make(rows.length(), 0),
    count: if rows.is_empty() {
      0
    } else {
      1
    },
  }
  meter.partition()
  for c in 0..<t.column_count() {
    let dictionary : Map[String?, Int32] = Map([])
    let codes = []
    for row in rows {
      meter.charge(1L)
      let code = match dictionary.get(row.cells[c]) {
        Some(code) => code
        None => {
          let code = dictionary.length()
          dictionary[row.cells[c]] = code
          code
        }
      }
      codes.push(code)
    }
    encoded.push(codes)
    cache[[c]] = { classes: codes, count: dictionary.length(), }
    meter.partition()
  }
  { table: t, rows, encoded, cache, meter, width: t.column_count(), }
}

///|
fn Index::get(self : Index, columns : Array[Int32]) -> Partition raise {
  self.meter.charge(columns.length().to_int64() + 1L)
  match self.cache.get(columns) {
    Some(p) => {
      self.meter.cache_hit()
      p
    }
    None => {
      let parent = columns.copy()
      let last = parent.pop().unwrap()
      let p = self.get(parent)
      let groups : Map[(Int32, Int32), Int32] = Map([])
      let classes = []
      for r in 0..<self.rows.length() {
        self.meter.charge(1L)
        let key = (p.classes[r], self.encoded[last][r])
        let code = match groups.get(key) {
          Some(code) => code
          None => {
            let code = groups.length()
            groups[key] = code
            code
          }
        }
        classes.push(code)
      }
      let result = { classes, count: groups.length(), }
      self.cache[columns.copy()] = result
      self.meter.partition()
      result
    }
  }
}

///|
fn Index::validate(
  self : Index,
  columns : Array[Int32],
) -> Unit raise @model.InputError {
  let mut previous = -1
  for c in columns {
    if c <= previous || c >= self.width {
      raise @model.Invalid(
        "partition columns must be sorted, distinct and in range",
      )
    }
    previous = c
  }
}

///|
pub fn Index::unique(self : Index, columns : Array[Int32]) -> Bool raise {
  self.validate(columns)
  self.get(columns).count == self.rows.length()
}

///|
pub fn Index::fd(
  self : Index,
  columns : Array[Int32],
  rhs : Int32,
) -> Bool raise {
  self.validate(columns)
  if rhs < 0 || rhs >= self.width || columns.contains(rhs) {
    raise @model.Invalid("invalid FD right side")
  }
  let joint = columns.copy()
  joint.push(rhs)
  joint.sort()
  self.get(columns).count == self.get(joint).count
}

///|
/// Linear witness extraction from equivalence classes, independent recheck is in verify.
pub fn Index::witness(
  self : Index,
  columns : Array[Int32],
  rhs~ : Int32? = None,
) -> @verify.Pair? raise {
  self.validate(columns)
  match rhs {
    Some(a) =>
      if a < 0 || a >= self.width {
        raise @model.Invalid("invalid witness right side")
      }
    None => ()
  }
  let p = self.get(columns)
  let seen : Map[Int32, Int32] = Map([])
  for i in 0..<self.rows.length() {
    self.meter.charge(1L)
    match seen.get(p.classes[i]) {
      Some(j) => {
        let differs = match rhs {
          Some(a) => self.encoded[a][i] != self.encoded[a][j]
          None => true
        }
        if differs {
          return Some({ first: self.rows[j].id, second: self.rows[i].id, })
        }
      }
      None => seen[p.classes[i]] = i
    }
  }
  None
}
