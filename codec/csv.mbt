///|
/// Strict comma-delimited UTF text, LF/CRLF records, quotes only at field start.
/// No dialect guessing, trimming, NULL inference, blank-record removal or deduplication.
pub fn parse_csv(input : String, table_id : String) -> @model.Table raise {
  if input.length() > 8388608 {
    raise @model.Invalid("CSV exceeds 8 Mi code units")
  }
  let chars = input.to_array()
  let records : Array[Array[String]] = []
  let mut row : Array[String] = []
  let mut value = StringBuilder()
  // 0: start, 1: unquoted, 2: quoted, 3: closed quote
  let mut state = 0
  let mut active = false
  let mut i = if chars.length() > 0 && chars[0] == '\uFEFF' { 1 } else { 0 }
  while i < chars.length() {
    let ch = chars[i]
    if state == 2 {
      if ch == '"' {
        state = 3
      } else {
        value.write_char(ch)
      }
      active = true
      i += 1
      continue
    }
    if state == 3 && ch == '"' {
      value.write_char('"')
      state = 2
      i += 1
      continue
    }
    if ch == ',' || ch == '\n' || ch == '\r' {
      row.push(value.to_string())
      value = StringBuilder()
      state = 0
      active = true
      if ch != ',' {
        if ch == '\r' {
          if i + 1 >= chars.length() || chars[i + 1] != '\n' {
            raise @model.Invalid("CSV bare CR outside quoted field")
          }
          i += 1
        }
        records.push(row)
        row = []
        active = false
      }
    } else if state == 3 {
      raise @model.Invalid("CSV characters after closing quote")
    } else if ch == '"' {
      if state != 0 {
        raise @model.Invalid("CSV quote inside unquoted field")
      }
      state = 2
      active = true
    } else {
      value.write_char(ch)
      state = 1
      active = true
    }
    i += 1
  }
  if state == 2 {
    raise @model.Invalid("CSV unclosed quoted field")
  }
  if active || !row.is_empty() {
    row.push(value.to_string())
    records.push(row)
  }
  if records.is_empty() {
    raise @model.Invalid("CSV requires a header")
  }
  let header = records[0]
  let rows : Array[@model.Row] = []
  for r in 1..<records.length() {
    if records[r].length() != header.length() {
      raise @model.Invalid("CSV record \{r}: width mismatch")
    }
    rows.push({ id: "r\{r}", cells: records[r].map(s => Some(s)), })
  }
  @model.table(table_id, header.map(name => { id: name, name, }), rows)
}
