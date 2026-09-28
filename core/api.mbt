///|
/// The bridge's public surface. Anything else is rejected before any effect.
pub(all) enum Route {
  Info
  Sessions
  Output(String)
  Send(String)
  Stop(String)
  Transcribe
  Asset(String)
} derive(Eq, Debug)

///|
pub extend Route with Eq::{not_equal, equal}

///|
pub extend Route with Debug::{to_repr}

///|
/// Static files served for LAN use; the same set is published as Worker assets.
pub let assets : Array[String] = [
  "index.html", "boot.js", "app.js", "style.css", "even_hub_sdk.js",
]

///|
pub fn content_type(file : String) -> String {
  if file.has_suffix(".html") {
    "text/html; charset=utf-8"
  } else if file.has_suffix(".js") {
    "text/javascript; charset=utf-8"
  } else if file.has_suffix(".css") {
    "text/css; charset=utf-8"
  } else {
    "application/octet-stream"
  }
}

///|
/// Orca terminal handles are opaque; accept only a conservative alphabet.
pub fn valid_session_id(id : String) -> Bool {
  if id.length() < 1 || id.length() > 128 {
    return false
  }
  for c in id {
    if !(c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '_' | '-')) {
      return false
    }
  }
  true
}

///|
pub fn not_found() -> ApiError {
  api_error(404, "not_found", "API がありません。")
}

///|
fn method_not_allowed() -> ApiError {
  api_error(
    405, "method_not_allowed", "このメソッドは使用できません。",
  )
}

///|
/// Strip the query string and fragment.
pub fn path_only(target : String) -> String {
  let chars = target.to_array()
  let mut end = 0
  while end < chars.length() && chars[end] != '?' && chars[end] != '#' {
    end += 1
  }
  String::from_array(chars[:end])
}

///|
pub fn is_api_path(path : String) -> Bool {
  path == "/api" || path.has_prefix("/api/")
}

///|
/// Resolve a request line to a route. OPTIONS is handled separately (CORS).
pub fn route(http_method : String, target : String) -> Result[Route, ApiError] {
  let path = path_only(target)
  let parts = path.split("/").map(fn(s) { s.to_owned() }).to_array()
  let get = http_method == "GET" || http_method == "HEAD"
  let post = http_method == "POST"
  match parts {
    ["", "api", "info"] =>
      if get {
        Ok(Info)
      } else {
        Err(method_not_allowed())
      }
    ["", "api", "sessions"] =>
      if get {
        Ok(Sessions)
      } else {
        Err(method_not_allowed())
      }
    ["", "api", "transcribe"] =>
      if post {
        Ok(Transcribe)
      } else {
        Err(method_not_allowed())
      }
    ["", "api", "sessions", id, action] if valid_session_id(id) =>
      match (action, get, post) {
        ("output", true, _) => Ok(Output(id))
        ("send", _, true) => Ok(Send(id))
        ("stop", _, true) => Ok(Stop(id))
        ("output", _, _) | ("send", _, _) | ("stop", _, _) =>
          Err(method_not_allowed())
        _ => Err(not_found())
      }
    ["", "api", ..] => Err(not_found())
    ["", ""] =>
      if get {
        Ok(Asset("index.html"))
      } else {
        Err(method_not_allowed())
      }
    ["", file] if assets.contains(file) =>
      if get {
        Ok(Asset(file))
      } else {
        Err(method_not_allowed())
      }
    _ => Err(not_found())
  }
}

///|
/// Constant-time comparison of the bearer credential.
pub fn authorized(header : String?, token : String) -> Bool {
  guard header is Some(value) && token.length() >= MIN_TOKEN_CHARS else {
    return false
  }
  let expected = "Bearer " + token
  let a = value.to_array()
  let b = expected.to_array()
  let mut diff = if a.length() == b.length() { 0 } else { 1 }
  for i in 0..<b.length() {
    let x = if i < a.length() { a[i].to_int() } else { 0 }
    diff = diff | (x ^ b[i].to_int())
  }
  diff == 0
}

///|
pub fn unauthorized() -> ApiError {
  api_error(
    401, "unauthorized", "ペアリング用トークンを確認してください。",
  )
}

///|
fn valid_operation_id(id : String) -> Bool {
  if id.length() < 8 || id.length() > 64 {
    return false
  }
  for c in id {
    if !(c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '-')) {
      return false
    }
  }
  true
}

///|
/// Normalize newlines and drop other control characters from a prompt.
pub fn sanitize_prompt(text : String) -> String {
  let out = StringBuilder()
  let chars = text.to_array()
  for i, c in chars {
    let code = c.to_int()
    if c == '\r' {
      if !(i + 1 < chars.length() && chars[i + 1] == '\n') {
        out.write_char('\n')
      }
    } else if c == '\n' || c == '\t' {
      out.write_char(c)
    } else if code >= 0x20 && code != 0x7f {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn is_blank(text : String) -> Bool {
  for c in text {
    if !(c is (' ' | '\n' | '\t' | '\u{3000}')) {
      return false
    }
  }
  true
}

///|
fn bad_request(message : String) -> ApiError {
  api_error(400, "bad_request", message)
}

///|
/// `{ operationId, text }` for a prompt.
pub fn parse_send_body(body : String) -> Result[(String, String), ApiError] {
  guard parse_json(body) is Some(json) && obj(json) is Some(map) else {
    return Err(bad_request("JSON を送信してください。"))
  }
  guard get_str(map, "operationId") is Some(op) && valid_operation_id(op) else {
    return Err(bad_request("操作 ID が不正です。"))
  }
  guard get_str(map, "text") is Some(raw) else {
    return Err(bad_request("指示を入力してください。"))
  }
  let text = sanitize_prompt(raw)
  if is_blank(text) {
    return Err(bad_request("指示を入力してください。"))
  }
  if text.length() > MAX_PROMPT_CHARS {
    return Err(bad_request("指示が長すぎます。"))
  }
  Ok((op, text))
}

///|
/// `{ operationId }` for an interrupt.
pub fn parse_stop_body(body : String) -> Result[String, ApiError] {
  guard parse_json(body) is Some(json) && obj(json) is Some(map) else {
    return Err(bad_request("JSON を送信してください。"))
  }
  guard get_str(map, "operationId") is Some(op) && valid_operation_id(op) else {
    return Err(bad_request("操作 ID が不正です。"))
  }
  Ok(op)
}

///|
/// Minimal RIFF/WAVE check before handing audio to a local recognizer.
pub fn looks_like_wav(header : Bytes) -> Bool {
  header.length() >= 44 &&
  header[0] == b'R' &&
  header[1] == b'I' &&
  header[2] == b'F' &&
  header[3] == b'F' &&
  header[8] == b'W' &&
  header[9] == b'A' &&
  header[10] == b'V' &&
  header[11] == b'E'
}

///|
/// 44-byte header for 16 kHz mono PCM16, as delivered by the G2 microphone.
pub fn wav_header(data_bytes : Int) -> Bytes {
  let buf = FixedArray::make(44, b'\x00')
  fn put_ascii(offset : Int, s : String) {
    for i, c in s.to_array() {
      buf[offset + i] = c.to_int().to_byte()
    }
  }

  fn put_u32(offset : Int, v : Int) {
    buf[offset] = (v & 0xff).to_byte()
    buf[offset + 1] = ((v >> 8) & 0xff).to_byte()
    buf[offset + 2] = ((v >> 16) & 0xff).to_byte()
    buf[offset + 3] = ((v >> 24) & 0xff).to_byte()
  }

  fn put_u16(offset : Int, v : Int) {
    buf[offset] = (v & 0xff).to_byte()
    buf[offset + 1] = ((v >> 8) & 0xff).to_byte()
  }

  put_ascii(0, "RIFF")
  put_u32(4, 36 + data_bytes)
  put_ascii(8, "WAVE")
  put_ascii(12, "fmt ")
  put_u32(16, 16)
  put_u16(20, 1)
  put_u16(22, 1)
  put_u32(24, 16000)
  put_u32(28, 32000)
  put_u16(32, 2)
  put_u16(34, 16)
  put_ascii(36, "data")
  put_u32(40, data_bytes)
  Bytes::from_array(buf)
}

///|
/// Allow a browser origin: same origin, or explicitly listed. Absent Origin
/// (native clients, the Worker relay) is allowed; authentication still applies.
pub fn origin_allowed(
  origin : String?,
  self_origin : String,
  allowed : String,
) -> Bool {
  match origin {
    None => true
    Some(o) =>
      o == self_origin ||
      allowed
      .split(",")
      .map(fn(s) { s.trim().to_owned() })
      .any(fn(s) { s.length() > 0 && s != "*" && s == o })
  }
}

///|
pub fn cors_headers(origin : String?) -> Array[(String, String)] {
  match origin {
    None => []
    Some(o) =>
      [
        ("Access-Control-Allow-Origin", o),
        ("Vary", "Origin"),
        ("Access-Control-Allow-Methods", "GET, POST, OPTIONS"),
        ("Access-Control-Allow-Headers", "Authorization, Content-Type"),
        ("Access-Control-Max-Age", "600"),
      ]
  }
}

///|
pub fn json_headers() -> Array[(String, String)] {
  [
    ("Content-Type", "application/json; charset=utf-8"),
    ("Cache-Control", "no-store"),
    ("X-Content-Type-Options", "nosniff"),
  ]
}
