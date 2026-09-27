///|
/// What the agent is doing. `Unknown` is never presented as success.
pub(all) enum AgentState {
  Working
  Waiting
  Idle
  Offline
  Unknown
} derive(Eq, Debug)

///|
pub fn AgentState::wire(self : AgentState) -> String {
  match self {
    Working => "working"
    Waiting => "waiting"
    Idle => "idle"
    Offline => "offline"
    Unknown => "unknown"
  }
}

///|
pub fn AgentState::from_wire(value : String) -> AgentState {
  match value {
    "working" => Working
    "waiting" => Waiting
    "idle" => Idle
    "offline" => Offline
    _ => Unknown
  }
}

///|
pub fn AgentState::label(self : AgentState) -> String {
  match self {
    Working => "実行中"
    Waiting => "入力待ち"
    Idle => "待機"
    Offline => "終了"
    Unknown => "状態不明"
  }
}

///|
pub(all) struct Session {
  id : String
  title : String
  project : String
  branch : String
  agent : String
  connected : Bool
  writable : Bool
  updated_at : Double?
  preview : String
} derive(Eq, Debug)

///|
pub(all) struct Output {
  session_id : String
  state : AgentState
  lines : Array[String]
  source : String
  truncated : Bool
  captured_at : Double
} derive(Eq, Debug)

///|
/// Distinguishes input acceptance from observed execution.
pub(all) struct Receipt {
  accepted : Bool
  message : String
  request_id : String?
} derive(Eq, Debug)

///|
/// Stable public error: never carries credentials or raw process output.
pub(all) struct ApiError {
  status : Int
  code : String
  message : String
} derive(Eq, Debug)

///|
pub(all) struct BridgeInfo {
  version : String
  speech : Bool
  runtime_ready : Bool
} derive(Eq, Debug)

///|
pub fn api_error(status : Int, code : String, message : String) -> ApiError {
  { status, code, message }
}

///|
pub fn Session::to_json(self : Session) -> Json {
  {
    "id": Json::string(self.id),
    "title": Json::string(self.title),
    "project": Json::string(self.project),
    "branch": Json::string(self.branch),
    "agent": Json::string(self.agent),
    "connected": Json::boolean(self.connected),
    "writable": Json::boolean(self.writable),
    "updatedAt": opt_num_json(self.updated_at),
    "preview": Json::string(self.preview),
  }
}

///|
pub fn Session::from_json(json : Json) -> Session? {
  guard obj(json) is Some(map) else { return None }
  guard get_str(map, "id") is Some(id) else { return None }
  Some({
    id,
    title: get_str(map, "title").unwrap_or(""),
    project: get_str(map, "project").unwrap_or(""),
    branch: get_str(map, "branch").unwrap_or(""),
    agent: get_str(map, "agent").unwrap_or(""),
    connected: get_bool(map, "connected").unwrap_or(false),
    writable: get_bool(map, "writable").unwrap_or(false),
    updated_at: get_num(map, "updatedAt"),
    preview: get_str(map, "preview").unwrap_or(""),
  })
}

///|
pub fn sessions_to_json(sessions : Array[Session]) -> Json {
  { "sessions": Json::array(sessions.map(Session::to_json)) }
}

///|
pub fn sessions_from_json(json : Json) -> Array[Session]? {
  guard obj(json) is Some(map) else { return None }
  guard get_arr(map, "sessions") is Some(items) else { return None }
  let out : Array[Session] = []
  for item in items {
    guard Session::from_json(item) is Some(session) else { return None }
    out.push(session)
  }
  Some(out)
}

///|
pub fn Output::to_json(self : Output) -> Json {
  {
    "sessionId": Json::string(self.session_id),
    "state": Json::string(self.state.wire()),
    "lines": Json::array(self.lines.map(Json::string)),
    "source": Json::string(self.source),
    "truncated": Json::boolean(self.truncated),
    "capturedAt": Json::number(self.captured_at),
  }
}

///|
pub fn Output::from_json(json : Json) -> Output? {
  guard obj(json) is Some(map) else { return None }
  guard get_arr(map, "lines") is Some(raw) else { return None }
  guard get_str(map, "sessionId") is Some(session_id) else { return None }
  let lines : Array[String] = []
  for line in raw {
    match line {
      String(s) => lines.push(s)
      _ => return None
    }
  }
  Some({
    session_id,
    state: AgentState::from_wire(get_str(map, "state").unwrap_or("")),
    lines,
    source: get_str(map, "source").unwrap_or("history"),
    truncated: get_bool(map, "truncated").unwrap_or(false),
    captured_at: get_num(map, "capturedAt").unwrap_or(0.0),
  })
}

///|
pub fn Receipt::to_json(self : Receipt) -> Json {
  {
    "accepted": Json::boolean(self.accepted),
    "message": Json::string(self.message),
    "requestId": opt_str_json(self.request_id),
  }
}

///|
pub fn Receipt::from_json(json : Json) -> Receipt? {
  guard obj(json) is Some(map) else { return None }
  guard get_bool(map, "accepted") is Some(accepted) else { return None }
  guard get_str(map, "message") is Some(message) else { return None }
  Some({ accepted, message, request_id: get_str(map, "requestId") })
}

///|
pub fn ApiError::to_json(self : ApiError) -> Json {
  {
    "error": {
      "code": Json::string(self.code),
      "message": Json::string(self.message),
    },
  }
}

///|
/// Read an error body; unreadable bodies become a generic failure for `status`.
pub fn ApiError::from_body(status : Int, body : String) -> ApiError {
  let fallback = api_error(
    status,
    "http_\{status}",
    "接続先から予期しない応答がありました。",
  )
  guard parse_json(body) is Some(json) else { return fallback }
  guard obj(json) is Some(map) else { return fallback }
  guard get_obj(map, "error") is Some(error) else { return fallback }
  match (get_str(error, "code"), get_str(error, "message")) {
    (Some(code), Some(message)) => api_error(status, code, message)
    _ => fallback
  }
}

///|
pub fn BridgeInfo::to_json(self : BridgeInfo) -> Json {
  {
    "version": Json::string(self.version),
    "speech": Json::boolean(self.speech),
    "runtimeReady": Json::boolean(self.runtime_ready),
  }
}

///|
pub fn BridgeInfo::from_json(json : Json) -> BridgeInfo? {
  guard obj(json) is Some(map) else { return None }
  Some({
    version: get_str(map, "version").unwrap_or(""),
    speech: get_bool(map, "speech").unwrap_or(false),
    runtime_ready: get_bool(map, "runtimeReady").unwrap_or(false),
  })
}
