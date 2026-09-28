///|
/// Mutable shell around the pure reader model: connection settings and the
/// glasses write queue.
struct Shell {
  model : @core.Model
  mut api : String
  mut token : String
  mut glasses : Bool
  mut glasses_note : String
  /// Last frame fully written to the glasses.
  mut written : @core.Frame?
  mut pending : @core.Frame?
  mut writing : Bool
}

///|
let shell : Shell = {
  model: @core.Model::new(),
  api: "",
  token: "",
  glasses: false,
  glasses_note: "G2 に接続しています...",
  written: None,
  pending: None,
  writing: false,
}

///|
let token_key : String = "even-g2-orca.token"

///|
let api_key : String = "even-g2-orca.api"

///|
fn base_url() -> String {
  if shell.api == "" {
    page_origin()
  } else {
    shell.api
  }
}

///|
fn network_error() -> @core.ApiError {
  @core.api_error(
    0, "network", "ブリッジに接続できません。操作後なら再送する前に出力を確認してください。",
  )
}

///|
fn request(
  http_method : String,
  path : String,
  body : Json?,
  k : (Result[Json, @core.ApiError]) -> Unit,
) -> Unit {
  let text = match body {
    Some(json) => json.stringify()
    None => ""
  }
  let timeout = if http_method == "POST" { 40000 } else { 20000 }
  http_text(http_method, base_url() + path, shell.token, text, timeout, fn(
    status,
    response,
  ) {
    if status == 0 {
      k(Err(network_error()))
    } else if status >= 200 && status < 300 {
      match @core.parse_json(response) {
        Some(json) => k(Ok(json))
        None => k(Err(@core.ApiError::from_body(status, "")))
      }
    } else {
      k(Err(@core.ApiError::from_body(status, response)))
    }
  })
}

///|
fn invalid_response() -> @core.ApiError {
  @core.api_error(
    502, "invalid_response", "ブリッジの応答形式に対応していません。バージョンを確認してください。",
  )
}

///|
fn dispatch(msg : @core.Msg) -> Unit {
  let effects = shell.model.update(msg)
  render()
  for effect in effects {
    run(effect)
  }
}

///|
fn gesture_of(kind : Int) -> @core.Gesture? {
  match kind {
    0 => Some(Tap)
    1 => Some(Up)
    2 => Some(Down)
    3 => Some(DoubleTap)
    5 | 6 | 7 => Some(Exit)
    9 => Some(Hold)
    10 => Some(Release)
    _ => None
  }
}

///|
fn run(effect : @core.Effect) -> Unit {
  match effect {
    LoadInfo =>
      request("GET", "/api/info", None, fn(result) {
        if result is Ok(json) && @core.BridgeInfo::from_json(json) is Some(info) {
          dispatch(Info(info))
        }
      })
    LoadSessions(generation) =>
      request("GET", "/api/sessions", None, fn(result) {
        match result {
          Ok(json) =>
            match @core.sessions_from_json(json) {
              Some(sessions) => dispatch(SessionsLoaded(generation, sessions))
              None => dispatch(SessionsFailed(generation, invalid_response()))
            }
          Err(e) => dispatch(SessionsFailed(generation, e))
        }
      })
    LoadOutput(generation, id) =>
      request("GET", "/api/sessions/\{id}/output", None, fn(result) {
        match result {
          Ok(json) =>
            match @core.Output::from_json(json) {
              Some(output) => dispatch(OutputLoaded(generation, output))
              None => dispatch(OutputFailed(generation, invalid_response()))
            }
          Err(e) => dispatch(OutputFailed(generation, e))
        }
      })
    Schedule(generation, ms) =>
      @js.set_timeout(fn() { dispatch(Tick(generation)) }, ms)
    SendPrompt(id, text) =>
      mutate("/api/sessions/\{id}/send", {
        "operationId": Json::string(@js.random_id()),
        "text": Json::string(text),
      })
    SendStop(id) =>
      mutate("/api/sessions/\{id}/stop", {
        "operationId": Json::string(@js.random_id()),
      })
    StartRecording(generation) =>
      g2_record_start(fn(ok, message) {
        if !ok {
          dispatch(VoiceFailed(generation, message))
        }
      })
    FinishRecording(generation) =>
      g2_record_finish(
        fn(pcm) {
          http_wav(
            base_url() + "/api/transcribe",
            shell.token,
            @core.wav_header(pcm.length()),
            pcm,
            130000,
            fn(status, body) {
              let text = if status >= 200 && status < 300 {
                match @core.parse_json(body) {
                  Some(json) =>
                    match @core.obj(json) {
                      Some(map) => @core.get_str(map, "text")
                      None => None
                    }
                  None => None
                }
              } else {
                None
              }
              match text {
                Some(t) => dispatch(Transcribed(generation, t))
                None => {
                  let message = if status == 0 {
                    network_error().message
                  } else {
                    @core.ApiError::from_body(status, body).message
                  }
                  dispatch(VoiceFailed(generation, message))
                }
              }
            },
          )
        },
        fn(message) { dispatch(VoiceFailed(generation, message)) },
      )
    CancelRecording => g2_record_cancel()
  }
}

///|
/// A new operation id per user action; the bridge suppresses duplicates.
fn mutate(path : String, body : Json) -> Unit {
  request("POST", path, Some(body), fn(result) {
    match result {
      Ok(json) =>
        match @core.Receipt::from_json(json) {
          Some(receipt) => dispatch(ActionDone(receipt))
          None => dispatch(ActionFailed(invalid_response()))
        }
      Err(e) => dispatch(ActionFailed(e))
    }
  })
}

///|
fn render() -> Unit {
  let model = shell.model
  let frame = model.frame()
  set_text("g2-title", frame.title)
  set_text("g2-body", frame.body)
  set_text("g2-footer", frame.footer)
  set_data(
    "screen",
    match model.screen {
      Setup => "Setup"
      Sessions => "Sessions"
      _ => "Session"
    },
  )
  let connection = match model.connection {
    Connecting => "接続中..."
    Online => "ブリッジに接続済み"
    Offline(message) => message
  }
  set_text(
    "status-bridge",
    if model.configured {
      connection
    } else {
      "未設定"
    },
  )
  set_text("status-glasses", shell.glasses_note)
  let target = match model.selected_session() {
    Some(s) => "送信先: \{s.title}（\{s.project}）"
    None => "セッションを開くと指示を送れます。"
  }
  set_text("compose-target", target)
  if shell.glasses {
    shell.pending = Some(frame)
    flush()
  }
}

///|
/// Serialize SDK writes and send only the containers that changed.
fn flush() -> Unit {
  if shell.writing || !shell.glasses {
    return
  }
  guard shell.pending is Some(next) else { return }
  shell.pending = None
  let previous = shell.written
  let fields = [
    (1, "heading", next.title, previous.map(fn(f) { f.title })),
    (2, "content", next.body, previous.map(fn(f) { f.body })),
    (3, "footer", next.footer, previous.map(fn(f) { f.footer })),
  ]
  shell.writing = true
  write_fields(fields, 0, fn(ok) {
    shell.writing = false
    if ok {
      shell.written = Some(next)
      flush()
    } else {
      shell.glasses = false
      shell.written = None
      shell.glasses_note = "G2 の表示更新に失敗しました。Even App でアプリを開き直してください。"
      dispatch(Gesture(Exit))
    }
  })
}

///|
fn write_fields(
  fields : Array[(Int, String, String, String?)],
  index : Int,
  done : (Bool) -> Unit,
) -> Unit {
  if index >= fields.length() {
    return done(true)
  }
  let (id, name, content, previous) = fields[index]
  if previous == Some(content) {
    write_fields(fields, index + 1, done)
  } else {
    g2_update(id, name, content, fn(ok) {
      if ok {
        write_fields(fields, index + 1, done)
      } else {
        done(false)
      }
    })
  }
}

///|
fn trim(text : String) -> String {
  text.trim().to_owned()
}

///|
/// Accept `#token=...&api=...` from a pairing link.
fn read_pairing() -> Unit {
  let fragment = take_fragment()
  if fragment == "" {
    return
  }
  for part in fragment.split("&") {
    let pair = part.to_owned()
    if pair.has_prefix("token=") {
      let token = trim(
        url_decode(pair.to_array()[6:].to_owned() |> String::from_array),
      )
      if token != "" {
        storage_set(token_key, token)
      }
    } else if pair.has_prefix("api=") {
      let api = trim(
        url_decode(pair.to_array()[4:].to_owned() |> String::from_array),
      )
      if valid_api(api) {
        storage_set(api_key, strip_slash(api))
      }
    }
  }
}

///|
fn valid_api(api : String) -> Bool {
  api == "" || api.has_prefix("https://") || api.has_prefix("http://")
}

///|
fn strip_slash(url : String) -> String {
  if url.has_suffix("/") {
    String::from_array(url.to_array()[:url.length() - 1])
  } else {
    url
  }
}

///|
fn load_settings() -> Unit {
  shell.token = storage_get(token_key)
  shell.api = storage_get(api_key)
  set_input("api-url", shell.api)
  set_input("token", shell.token)
}

///|
fn save_settings() -> Unit {
  let api = strip_slash(trim(input_value("api-url")))
  let token = trim(input_value("token"))
  if !valid_api(api) {
    set_text(
      "settings-note", "接続先は http:// か https:// で始まる URL にしてください。",
    )
    return
  }
  if token.length() < @core.MIN_TOKEN_CHARS {
    set_text(
      "settings-note", "ペアリング用トークンを確認してください。",
    )
    return
  }
  if page_protocol() == "https:" && api.has_prefix("http://") {
    set_text(
      "settings-note", "HTTPS のページから http:// の接続先には接続できません。",
    )
    return
  }
  storage_set(api_key, api)
  storage_set(token_key, token)
  shell.api = api
  shell.token = token
  set_text("settings-note", "保存しました。")
  dispatch(Configured(true))
}

///|
fn clear_settings() -> Unit {
  storage_remove(api_key)
  storage_remove(token_key)
  shell.api = ""
  shell.token = ""
  set_input("api-url", "")
  set_input("token", "")
  set_text(
    "settings-note", "この端末から接続情報を削除しました。",
  )
  dispatch(Configured(false))
}

///|
fn bind_controls() -> Unit {
  on_click("btn-up", fn() { dispatch(Gesture(Up)) })
  on_click("btn-down", fn() { dispatch(Gesture(Down)) })
  on_click("btn-tap", fn() { dispatch(Gesture(Tap)) })
  on_click("btn-double", fn() { dispatch(Gesture(DoubleTap)) })
  on_press("btn-hold", fn() { dispatch(Gesture(Hold)) }, fn() {
    dispatch(Gesture(Release))
  })
  on_click("compose-send", fn() {
    let text = trim(input_value("draft"))
    if text != "" {
      dispatch(Draft(text))
      if shell.model.screen == ConfirmPrompt {
        set_input("draft", "")
      }
    }
  })
  on_click("settings-save", save_settings)
  on_click("settings-clear", clear_settings)
  on_key(fn(key) {
    match key {
      "ArrowUp" => dispatch(Gesture(Up))
      "ArrowDown" => dispatch(Gesture(Down))
      "Enter" => dispatch(Gesture(Tap))
      "Escape" | "Backspace" => dispatch(Gesture(DoubleTap))
      _ => ()
    }
  })
}

///|
fn main {
  read_pairing()
  load_settings()
  bind_controls()
  g2_connect(
    fn(kind) {
      if gesture_of(kind) is Some(gesture) {
        dispatch(Gesture(gesture))
      }
    },
    fn(ok, message) {
      shell.glasses = ok
      shell.written = None
      shell.glasses_note = if ok { "G2 に表示中" } else { message }
      render()
    },
  )
  dispatch(Configured(shell.token != ""))
}
