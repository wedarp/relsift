///|
/// A session can yield between candidates; exhausted budgets are terminal.
pub(all) enum Progress {
  Running
  Finished
  BudgetExhausted(String)
}

///|
pub struct Session {
  priv table : @model.Table
  priv meter : @budget.Meter
  priv mut index : @partition.Index?
  priv fds : Array[@dependency.Fd]
  priv uccs : Array[@unique.Ucc]
  priv mut progress : Progress
  priv mut fd_complete : Bool
  priv mut ucc_complete : Bool
  priv mut size : Int32
  priv mut chosen : Array[Int32]
  priv mut rhs : Int32
}

///|
/// Construction validates limits, but does not allocate the partition index.
pub fn session(
  table : @model.Table,
  limits~ : @budget.Limits = @budget.defaults(),
) -> Session raise {
  {
    table,
    meter: @budget.meter(limits),
    index: None,
    fds: [],
    uccs: [],
    progress: Running,
    fd_complete: false,
    ucc_complete: false,
    size: 0,
    chosen: [],
    rhs: 0,
  }
}

///|
pub fn Session::progress(self : Session) -> Progress {
  self.progress
}

///|
/// Move to the next lexicographic combination, then the next width.
fn Session::advance(self : Session) -> Unit {
  let width = self.table.column_count()
  let mut i = self.size - 1
  while i >= 0 {
    if self.chosen[i] < width - self.size + i {
      self.chosen[i] += 1
      for j in (i + 1)..<self.size {
        self.chosen[j] = self.chosen[j - 1] + 1
      }
      self.rhs = 0
      return
    }
    i -= 1
  }
  self.size += 1
  // At the end of a phase no oversized array is allocated.
  self.chosen = if self.size <= width {
    Array::makei(self.size, i => i)
  } else {
    []
  }
  self.rhs = 0
}

///|
/// Normalize the cursor without spending a candidate or touching row values.
fn Session::normalize(self : Session) -> Unit {
  let width = self.table.column_count()
  if !self.fd_complete {
    let max_lhs = Int32::min(
      self.meter.limits.max_lhs,
      Int32::max(0, width - 1),
    )
    while self.size <= max_lhs {
      while self.rhs < width && self.chosen.contains(self.rhs) {
        self.rhs += 1
      }
      if self.rhs < width {
        return
      }
      self.advance()
    }
    self.fd_complete = true
    self.size = 0
    self.chosen = []
    self.rhs = 0
  }
  if self.size > Int32::min(width, self.meter.limits.max_ucc_width) {
    self.ucc_complete = true
    self.progress = Finished
  }
}

///|
/// Process at most quota candidates, retaining the index, proofs and cursor.
/// A quota is not a time slice: one candidate can still scan the entire table.
pub fn Session::step(self : Session, quota : Int32) -> Progress raise {
  if quota < 0 {
    raise @model.Invalid("negative step quota")
  }
  if quota == 0 || !(self.progress is Running) {
    return self.progress
  }
  try {
    let idx = match self.index {
      Some(idx) => idx
      None => {
        let idx = @partition.index(self.table, self.meter)
        self.index = Some(idx)
        idx
      }
    }
    self.normalize()
    let mut processed = 0
    while processed < quota && self.progress is Running {
      self.meter.charge(self.chosen.length().to_int64() + 1L)
      if !self.fd_complete {
        @dependency.consider(idx, self.chosen, self.rhs, self.fds)
        self.rhs += 1
      } else {
        @unique.consider(idx, self.chosen, self.uccs)
        self.advance()
      }
      processed += 1
      self.normalize()
    }
  } catch {
    @budget.Exhausted(reason) => self.progress = BudgetExhausted(reason)
    error => raise error
  }
  self.progress
}

///|
/// Returned arrays are detached, so editing a snapshot cannot corrupt pruning.
pub fn Session::snapshot(self : Session) -> Discovery {
  let status = match self.progress {
    Running => @budget.Partial("yielded")
    Finished => @budget.CompleteInDomain
    BudgetExhausted(reason) => @budget.Partial(reason)
  }
  {
    table_id: self.table.id,
    row_count: self.table.row_count(),
    column_count: self.table.column_count(),
    null_policy: self.table.policy,
    limits: self.meter.limits,
    status,
    fd_complete: self.fd_complete,
    ucc_complete: self.ucc_complete,
    fds: self.fds.map(f => {
      ..f,
      lhs: f.lhs.copy(),
      deletions: f.deletions.copy(),
    }),
    uccs: self.uccs.map(k => {
      columns: k.columns.copy(),
      deletions: k.deletions.copy(),
    }),
    usage: self.meter.usage(),
    degenerate: self.table.row_count() <= 1,
  }
}
