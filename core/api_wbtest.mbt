///|
test "route accepts only the documented surface" {
  @debug.debug_inspect(route("GET", "/api/info?x=1"), content="Ok(Info)")
  @debug.debug_inspect(route("GET", "/api/sessions"), content="Ok(Sessions)")
  @debug.debug_inspect(
    route("GET", "/api/sessions/term_a-1/output"),
    content="Ok(Output(\"term_a-1\"))",
  )
  @debug.debug_inspect(
    route("POST", "/api/sessions/term_a/send"),
    content="Ok(Send(\"term_a\"))",
  )
  @debug.debug_inspect(
    route("POST", "/api/sessions/term_a/stop"),
    content="Ok(Stop(\"term_a\"))",
  )
  @debug.debug_inspect(
    route("POST", "/api/transcribe"),
    content="Ok(Transcribe)",
  )
  @debug.debug_inspect(route("GET", "/"), content="Ok(Asset(\"index.html\"))")
  @debug.debug_inspect(route("GET", "/app.js"), content="Ok(Asset(\"app.js\"))")
  @debug.debug_inspect(
    route("GET", "/api/sessions/term_a/send").unwrap_err().status,
    content="405",
  )
  @debug.debug_inspect(
    route("GET", "/api/sessions/../x/output").unwrap_err().status,
    content="404",
  )
  @debug.debug_inspect(
    route("GET", "/api/sessions/a%2Fb/output").unwrap_err().status,
    content="404",
  )
  @debug.debug_inspect(route("GET", "/.env").unwrap_err().status, content="404")
  @debug.debug_inspect(
    route("GET", "/api/other").unwrap_err().status,
    content="404",
  )
}

///|
test "authorized compares the whole bearer credential" {
  let token = "abcdefghijklmnopqrstuvwxyz"
  @debug.debug_inspect(
    authorized(Some("Bearer " + token), token),
    content="true",
  )
  @debug.debug_inspect(
    authorized(Some("Bearer " + token + "x"), token),
    content="false",
  )
  @debug.debug_inspect(authorized(Some("Bearer abc"), token), content="false")
  @debug.debug_inspect(authorized(None, token), content="false")
  @debug.debug_inspect(
    authorized(Some("Bearer short"), "short"),
    content="false",
  )
}

///|
test "request bodies are validated" {
  @debug.debug_inspect(
    parse_send_body(
      "{\"operationId\":\"op-12345678\",\"text\":\"hi\\r\\nthere\\u0007\"}",
    ),
    content="Ok((\"op-12345678\", \"hi\\nthere\"))",
  )
  @debug.debug_inspect(
    parse_send_body("{\"operationId\":\"op-12345678\",\"text\":\" \\n\"}").unwrap_err().code,
    content=(
      #|"bad_request"
    ),
  )
  @debug.debug_inspect(
    parse_send_body("{\"operationId\":\"bad id!\",\"text\":\"x\"}").unwrap_err().message,
    content=(
      #|"操作 ID が不正です。"
    ),
  )
  @debug.debug_inspect(
    parse_stop_body("{\"operationId\":\"abcdefgh\"}"),
    content="Ok(\"abcdefgh\")",
  )
  @debug.debug_inspect(parse_stop_body("[]").unwrap_err().status, content="400")
}

///|
test "wav header describes 16 kHz mono PCM16" {
  let header = wav_header(32000)
  @debug.debug_inspect(header.length(), content="44")
  @debug.debug_inspect(looks_like_wav(header), content="true")
  @debug.debug_inspect(
    header[40].to_int() + (header[41].to_int() << 8),
    content="32000",
  )
  @debug.debug_inspect(looks_like_wav(b"RIFF"), content="false")
}

///|
test "origins are same-origin or explicitly listed" {
  @debug.debug_inspect(origin_allowed(None, "https://a", ""), content="true")
  @debug.debug_inspect(
    origin_allowed(Some("https://a"), "https://a", ""),
    content="true",
  )
  @debug.debug_inspect(
    origin_allowed(Some("https://b"), "https://a", ""),
    content="false",
  )
  @debug.debug_inspect(
    origin_allowed(Some("https://b"), "https://a", " https://b ,https://c"),
    content="true",
  )
  @debug.debug_inspect(
    origin_allowed(Some("https://b"), "https://a", "*"),
    content="false",
  )
}

///|
test "operation log replays and refuses conflicting reuse" {
  let log = OperationLog::new()
  @debug.debug_inspect(log.begin("op1", "send:a", 0), content="Fresh")
  @debug.debug_inspect(log.begin("op1", "send:a", 1), content="InFlight")
  log.finish("op1", 200, "{}")
  @debug.debug_inspect(
    log.begin("op1", "send:a", 2),
    content="Replay(200, \"{}\")",
  )
  @debug.debug_inspect(log.begin("op1", "send:b", 3), content="Conflict")
  @debug.debug_inspect(
    log.begin("op1", "send:b", OPERATION_RETENTION_MS + 10),
    content="Fresh",
  )
  @debug.debug_inspect(log.length(), content="1")
  log.forget("op1")
  @debug.debug_inspect(log.begin("op1", "send:c", 0), content="Fresh")
}

///|
test "relay forwards only authenticated API routes" {
  let plan = fn(
    http_method : String,
    path : String,
    origin : String?,
    auth : String?,
    bridge : String,
  ) {
    relay_plan(http_method, path, "https://app", origin, auth, bridge, "", true).0
  }
  @debug.debug_inspect(plan("GET", "/", None, None, ""), content="Assets")
  @debug.debug_inspect(
    plan(
      "GET",
      "/api/sessions",
      None,
      Some("Bearer t"),
      "https://bridge.example.com/",
    ),
    content="Forward(\"https://bridge.example.com/api/sessions\")",
  )
  @debug.debug_inspect(
    plan("GET", "/api/sessions", None, None, "https://b.example.com")
    is Respond(401, _),
    content="true",
  )
  @debug.debug_inspect(
    plan("GET", "/api/x", None, Some("Bearer t"), "https://b.example.com")
    is Respond(404, _),
    content="true",
  )
  @debug.debug_inspect(
    plan(
      "GET",
      "/api/info",
      Some("https://evil"),
      Some("Bearer t"),
      "https://b.example.com",
    )
    is Respond(403, _),
    content="true",
  )
  @debug.debug_inspect(
    plan("OPTIONS", "/api/info", Some("https://app"), None, ""),
    content="Preflight",
  )
  @debug.debug_inspect(
    plan("GET", "/api/info", None, Some("Bearer t"), "http://b.example.com")
    is Respond(503, _),
    content="true",
  )
  @debug.debug_inspect(
    plan(
      "GET",
      "/api/info",
      None,
      Some("Bearer t"),
      "https://b.example.com/path",
    )
    is Respond(503, _),
    content="true",
  )
  let (_, headers) = relay_plan(
    "GET",
    "/api/info",
    "https://app",
    Some("https://app"),
    Some("Bearer t"),
    "https://b.example.com",
    "",
    true,
  )
  @debug.debug_inspect(
    headers.contains(("Access-Control-Allow-Origin", "https://app")),
    content="true",
  )
}
