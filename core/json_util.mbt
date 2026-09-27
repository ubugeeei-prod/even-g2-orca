///|
/// Defensive accessors for untrusted JSON: wrong types read as absent.
pub fn obj(json : Json) -> Map[String, Json]? {
  match json {
    Object(map) => Some(map)
    _ => None
  }
}

///|
pub fn get_str(map : Map[String, Json], key : String) -> String? {
  match map.get(key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
pub fn get_bool(map : Map[String, Json], key : String) -> Bool? {
  match map.get(key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
pub fn get_num(map : Map[String, Json], key : String) -> Double? {
  match map.get(key) {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
}

///|
pub fn get_obj(map : Map[String, Json], key : String) -> Map[String, Json]? {
  match map.get(key) {
    Some(Object(m)) => Some(m)
    _ => None
  }
}

///|
pub fn get_arr(map : Map[String, Json], key : String) -> Array[Json]? {
  match map.get(key) {
    Some(Array(a)) => Some(a)
    _ => None
  }
}

///|
/// Parse a JSON document, treating malformed text as absent.
pub fn parse_json(text : String) -> Json? {
  try @json.parse(text) catch {
    _ => None
  } noraise {
    json => Some(json)
  }
}

///|
fn opt_num_json(value : Double?) -> Json {
  match value {
    Some(n) => Json::number(n)
    None => Json::null()
  }
}

///|
fn opt_str_json(value : String?) -> Json {
  match value {
    Some(s) => Json::string(s)
    None => Json::null()
  }
}
