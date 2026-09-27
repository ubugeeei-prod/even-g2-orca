///|
/// Where to reach Orca's local authenticated RPC, from `orca-runtime.json`.
pub(all) struct RuntimeEndpoint {
  endpoint : String
  auth_token : String
  runtime_id : String
} derive(Eq, Debug)

///|
pub fn orca_unavailable() -> ApiError {
  api_error(
    503, "orca_unavailable", "Mac で Orca を起動してください。",
  )
}

///|
pub fn delivery_unknown() -> ApiError {
  api_error(
    502, "delivery_unknown", "操作の結果を確認できません。再送する前に出力を確認してください。",
  )
}

///|
/// Choose the local socket transport; websocket endpoints are never used.
pub fn runtime_endpoint(metadata : String) -> Result[RuntimeEndpoint, ApiError] {
  let incompatible = api_error(
    503, "orca_incompatible", "Orca のローカル接続情報を読み取れません。",
  )
  guard parse_json(metadata) is Some(json) else { return Err(incompatible) }
  guard obj(json) is Some(map) else { return Err(incompatible) }
  guard get_str(map, "authToken") is Some(auth_token) && auth_token.length() > 0 else {
    return Err(incompatible)
  }
  let runtime_id = get_str(map, "runtimeId").unwrap_or("")
  guard get_arr(map, "transports") is Some(transports) else {
    return Err(incompatible)
  }
  for transport in transports {
    guard obj(transport) is Some(t) else { continue }
    match (get_str(t, "kind"), get_str(t, "endpoint")) {
      (Some("unix"), Some(endpoint)) | (Some("named-pipe"), Some(endpoint)) =>
        if endpoint.length() > 0 {
          return Ok({ endpoint, auth_token, runtime_id, })
        }
      _ => ()
    }
  }
  Err(incompatible)
}

///|
/// One newline-delimited JSON-RPC request line.
pub fn rpc_request(
  id : String,
  auth_token : String,
  rpc_method : String,
  params : Json,
) -> String {
  let request : Json = {
    "id": Json::string(id),
    "authToken": Json::string(auth_token),
    "method": Json::string(rpc_method),
    "params": params,
  }
  request.stringify() + "\n"
}

///|
pub(all) enum RpcFrame {
  Keepalive
  Done(Json)
  Failed(ApiError)
} derive(Eq, Debug)

///|
/// Interpret one response line. Frames for another request or runtime are
/// rejected rather than silently accepted.
pub fn rpc_frame(line : String, id : String, runtime_id : String) -> RpcFrame {
  let invalid = RpcFrame::Failed(
    api_error(
      502, "orca_invalid_response", "Orca の応答形式に対応していません。",
    ),
  )
  guard parse_json(line) is Some(json) else { return invalid }
  guard obj(json) is Some(map) else { return invalid }
  if get_bool(map, "_keepalive") == Some(true) {
    return Keepalive
  }
  if get_str(map, "id") != Some(id) {
    return invalid
  }
  if get_obj(map, "_meta") is Some(meta) &&
    get_str(meta, "runtimeId") is Some(rid) &&
    runtime_id != "" &&
    rid != runtime_id {
    return invalid
  }
  match (get_bool(map, "ok"), map.get("result")) {
    (Some(true), Some(result)) => Done(result)
    (Some(false), _) => {
      let code = match get_obj(map, "error") {
        Some(error) => get_str(error, "code").unwrap_or("orca_error")
        None => "orca_error"
      }
      Failed(
        api_error(
          502, code, "Orca が操作を受け付けませんでした。Mac 側で状態を確認してください。",
        ),
      )
    }
    _ => invalid
  }
}

///|
/// The `{ ok, result }` envelope printed by `orca ... --json`.
pub fn cli_result(stdout : String) -> Result[Json, ApiError] {
  guard parse_json(stdout) is Some(json) else { return Err(delivery_unknown()) }
  guard obj(json) is Some(map) else { return Err(delivery_unknown()) }
  match (get_bool(map, "ok"), map.get("result")) {
    (Some(true), Some(result)) => Ok(result)
    (Some(false), _) => {
      let code = match get_obj(map, "error") {
        Some(error) => get_str(error, "code").unwrap_or("orca_error")
        None => "orca_error"
      }
      Err(
        api_error(
          502, code, "Orca が操作を拒否しました。Mac 側を確認してください。",
        ),
      )
    }
    _ => Err(delivery_unknown())
  }
}

///|
fn strip_prefix(text : String, prefix : String) -> String {
  if text.has_prefix(prefix) {
    text.to_array()[prefix.length():].to_owned() |> String::from_array
  } else {
    text
  }
}

///|
fn one_line(text : String) -> String {
  let lines = clean_terminal_text(text)
    .split("\n")
    .map(fn(s) { trim_end_spaces(s.to_owned()) })
    .filter(fn(s) { s.length() > 0 })
    .to_array()
  match lines {
    [] => ""
    _ => lines[lines.length() - 1]
  }
}

///|
/// Agent sessions from `terminal.list`, newest output first. Plain shells and
/// orphaned terminals are excluded because they cannot take agent prompts.
pub fn sessions_from_list(result : Json) -> Result[Array[Session], ApiError] {
  guard obj(result) is Some(map) && get_arr(map, "terminals") is Some(terminals) else {
    return Err(
      api_error(
        502, "orca_invalid_response", "Orca の応答形式に対応していません。",
      ),
    )
  }
  let sessions : Array[Session] = []
  for item in terminals {
    guard obj(item) is Some(t) else { continue }
    guard get_str(t, "handle") is Some(id) else { continue }
    guard get_str(t, "agentIdentity") is Some(agent) && agent.length() > 0 else {
      continue
    }
    if get_bool(t, "orphaned") == Some(true) {
      continue
    }
    let title = clean_terminal_text(get_str(t, "title").unwrap_or(agent))
    let project = basename(get_str(t, "worktreePath").unwrap_or(""))
    sessions.push({
      id,
      title: if title.length() > 0 {
        title
      } else {
        agent
      },
      project: if project.length() > 0 {
        project
      } else {
        "Workspace"
      },
      branch: strip_prefix(get_str(t, "branch").unwrap_or(""), "refs/heads/"),
      agent,
      connected: get_bool(t, "connected").unwrap_or(false),
      writable: get_bool(t, "writable").unwrap_or(false),
      updated_at: get_num(t, "lastOutputAt"),
      preview: one_line(get_str(t, "preview").unwrap_or("")),
    })
  }
  sessions.sort_by(fn(a, b) {
    b.updated_at.unwrap_or(0.0).compare(a.updated_at.unwrap_or(0.0))
  })
  Ok(sessions)
}

///|
/// `terminal.agentStatus` says whether an agent (not a bare shell) is running.
pub fn is_running_agent(result : Json) -> Bool {
  match obj(result) {
    Some(map) =>
      match get_obj(map, "agentStatus") {
        Some(status) => get_bool(status, "isRunningAgent") == Some(true)
        None => false
      }
    None => false
  }
}

///|
pub fn not_an_agent() -> ApiError {
  api_error(
    409, "not_an_agent", "このセッションではエージェントが動いていません。Mac で確認してください。",
  )
}

///|
/// Combine `terminal.read` (screen) and `terminal.agentStatus` into one
/// snapshot. States that cannot be read are reported as unknown.
pub fn output_from_read(
  id : String,
  read : Json,
  status : Json,
  now : Double,
) -> Result[Output, ApiError] {
  let unsupported = api_error(
    409, "unsupported_session", "この表示形式は未対応です。ターミナル表示のセッションを選んでください。",
  )
  guard obj(read) is Some(r) && get_obj(r, "terminal") is Some(terminal) else {
    return Err(unsupported)
  }
  guard get_arr(terminal, "tail") is Some(tail) else { return Err(unsupported) }
  let lines : Array[String] = []
  for line in tail {
    if line is String(s) {
      lines.push(trim_end_spaces(clean_terminal_text(s)))
    }
  }
  let start = if lines.length() > MAX_OUTPUT_LINES {
    lines.length() - MAX_OUTPUT_LINES
  } else {
    0
  }
  let agent = match obj(status) {
    Some(m) => get_obj(m, "agentStatus")
    None => None
  }
  let running = match agent {
    Some(a) => get_bool(a, "isRunningAgent") == Some(true)
    None => false
  }
  let raw = match agent {
    Some(a) => get_str(a, "status").unwrap_or("")
    None => ""
  }
  let state : AgentState = if get_str(terminal, "status") == Some("exited") {
    Offline
  } else if !running {
    Idle
  } else {
    match raw {
      "working" => Working
      "waiting" | "permission" | "input-required" => Waiting
      "idle" => Idle
      _ => Unknown
    }
  }
  Ok({
    session_id: id,
    state,
    lines: drop_trailing_blank(lines[start:].to_owned()),
    source: if get_str(terminal, "source") == Some("screen") {
      "screen"
    } else {
      "history"
    },
    truncated: get_bool(terminal, "truncated") == Some(true) || start > 0,
    captured_at: now,
  })
}

///|
/// CLI arguments for a prompt. The text is one argv entry; no shell is used.
pub fn send_args(id : String, text : String) -> Array[String] {
  [
    "terminal", "send", "--terminal", id, "--text", text, "--enter", "--wait-submit",
    "2", "--json",
  ]
}

///|
/// Ctrl-C as an interrupt-style input.
pub fn interrupt_args(id : String) -> Array[String] {
  [
    "terminal", "send", "--terminal", id, "--text", "\u{3}", "--interrupt", "--json",
  ]
}

///|
/// Interpret the durable receipt of `terminal send`. Only an observed
/// `turn_started` stage is reported as execution.
pub fn receipt_from_send(
  result : Json,
  interrupt : Bool,
) -> Result[Receipt, ApiError] {
  guard obj(result) is Some(map) && get_obj(map, "send") is Some(send) else {
    return Err(delivery_unknown())
  }
  let accepted = get_bool(send, "accepted") == Some(true)
  let prompt = get_obj(send, "prompt")
  let observed = match prompt {
    Some(p) =>
      match get_arr(p, "stages") {
        Some(stages) => stages.contains(Json::string("turn_started"))
        None => false
      }
    None => false
  }
  let request_id = match prompt {
    Some(p) => get_str(p, "requestId")
    None => None
  }
  let message = if !accepted {
    "Orca が操作を受け付けませんでした。"
  } else if interrupt {
    "停止の入力を送りました。止まったか出力で確認してください。"
  } else if observed {
    "指示を送信し、実行開始を確認しました。"
  } else {
    "入力は受け付けられました。実行開始は未確認です。再送する前に出力を確認してください。"
  }
  Ok({ accepted, message, request_id, })
}
