///|
pub fn object(value : Json) -> Map[String, Json] raise @model.InputError {
  match value {
    Object(m) => m
    _ => raise @model.Invalid("expected object")
  }
}

///|
pub fn array(value : Json) -> Array[Json] raise @model.InputError {
  match value {
    Array(a) => a
    _ => raise @model.Invalid("expected array")
  }
}

///|
pub fn string(value : Json) -> String raise @model.InputError {
  match value {
    String(s) => s
    _ => raise @model.Invalid("expected string")
  }
}

///|
pub fn field(
  m : Map[String, Json],
  name : String,
) -> Json raise @model.InputError {
  match m.get(name) {
    Some(v) => v
    None => raise @model.Invalid("missing field: " + name)
  }
}

///|
pub fn only(
  m : Map[String, Json],
  keys : Array[String],
) -> Unit raise @model.InputError {
  for key, _ in m {
    if !keys.contains(key) {
      raise @model.Invalid("unknown field: " + key)
    }
  }
}

///|
pub fn parse_json(input : String) -> Json raise {
  if input.length() > 8388608 {
    raise @model.Invalid("JSON exceeds 8 Mi code units")
  }
  @json.parse(input, reject_duplicate_keys=true, max_nesting_depth=64)
}

///|
/// Version 1 envelope, explicit IDs and cells of String or JSON null only.
pub fn parse_tables(input : String) -> Array[@model.Table] raise {
  let root = object(parse_json(input))
  only(root, ["schema_version", "null_policy", "tables"])
  if field(root, "schema_version") != Json::number(1.0) {
    raise @model.Invalid("schema_version must be 1")
  }
  let policy = match string(field(root, "null_policy")) {
    "reject" => @model.RejectNull
    "equal" => @model.NullAsValue
    _ => raise @model.Invalid("null_policy must be reject or equal")
  }
  let tables = []
  let seen : Map[String, Bool] = Map([])
  for value in array(field(root, "tables")) {
    let t = object(value)
    only(t, ["id", "columns", "rows"])
    let id = string(field(t, "id"))
    if seen.contains(id) {
      raise @model.Invalid("duplicate table ID")
    }
    seen[id] = true
    let columns = array(field(t, "columns")).map(value => {
      let c = object(value)
      only(c, ["id", "name"])
      @model.Column::{
        id: string(field(c, "id")),
        name: string(field(c, "name")),
      }
    })
    let rows = array(field(t, "rows")).map(value => {
      let r = object(value)
      only(r, ["id", "cells"])
      let cells = array(field(r, "cells")).map(v => {
        match v {
          Null => None
          String(s) => Some(s)
          _ => raise @model.Invalid("cell must be string or null")
        }
      })
      @model.Row::{ id: string(field(r, "id")), cells, }
    })
    tables.push(@model.table(id, columns, rows, policy~))
  }
  tables.sort_by((a, b) => a.id.lexical_compare(b.id))
  tables
}
