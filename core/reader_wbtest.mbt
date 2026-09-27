///|
fn session(id : String, title : String) -> Session {
  {
    id,
    title,
    project: "app",
    branch: "main",
    agent: "claude",
    connected: true,
    writable: true,
    updated_at: None,
    preview: "",
  }
}

///|
fn output(id : String, lines : Array[String], at : Double) -> Output {
  {
    session_id: id,
    state: Working,
    lines,
    source: "screen",
    truncated: false,
    captured_at: at,
  }
}

///|
fn ready() -> Model raise {
  let model = Model::new()
  let effects = model.update(Configured(true))
  @debug.debug_inspect(effects, content="[LoadInfo, LoadSessions(1)]")
  model.update(Info({ version: "1", speech: true, runtime_ready: true, }))
  |> ignore
  model.update(SessionsLoaded(1, [session("a", "Alpha"), session("b", "Beta")]))
  |> ignore
  model
}

///|
fn many(n : Int) -> Array[String] {
  Array::makei(n, fn(i) { "line \{i}" })
}

///|
test "session list keeps the cursor by id across reordering" {
  let model = ready()
  @debug.debug_inspect(model.update(Gesture(Down)), content="[]")
  @debug.debug_inspect(model.cursor, content="Some(\"b\")")
  model.update(SessionsLoaded(1, [session("c", "C"), session("b", "Beta")]))
  |> ignore
  @debug.debug_inspect(model.cursor, content="Some(\"b\")")
  @debug.debug_inspect(model.frame().body.contains("> Beta"), content="true")
}

///|
test "stale responses from a previous session are discarded" {
  let model = ready()
  @debug.debug_inspect(
    model.update(Gesture(Tap)),
    content="[LoadOutput(2, \"a\")]",
  )
  @debug.debug_inspect(
    model.update(Gesture(DoubleTap)),
    content="[LoadSessions(3)]",
  )
  @debug.debug_inspect(
    model.update(OutputLoaded(2, output("a", ["old"], 1))),
    content="[]",
  )
  @debug.debug_inspect(model.shown, content="None")
  @debug.debug_inspect(model.update(Tick(2)), content="[]")
}

///|
test "reading follows new output until the user pages back" {
  let model = ready()
  model.update(Gesture(Tap)) |> ignore
  @debug.debug_inspect(
    model.update(OutputLoaded(2, output("a", many(14), 1))),
    content="[Schedule(2, 2000)]",
  )
  @debug.debug_inspect(model.page, content="2")
  // The newest page is full; only the oldest page may be short.
  @debug.debug_inspect(model.frame().body.split("\n").count(), content="6")
  @debug.debug_inspect(
    model.frame().footer,
    content=(
      #|"3/3 追従  タップ 操作"
    ),
  )
  model.update(Gesture(Up)) |> ignore
  @debug.debug_inspect(model.follow, content="false")
  model.update(OutputLoaded(2, output("a", many(20), 2))) |> ignore
  @debug.debug_inspect(
    model.shown.map(fn(o) { o.lines.length() }),
    content="Some(14)",
  )
  @debug.debug_inspect(
    model.frame().footer,
    content=(
      #|"2/3 一時停止 新着あり  タップ 操作"
    ),
  )
  model.update(Gesture(Down)) |> ignore
  model.update(Gesture(Down)) |> ignore
  @debug.debug_inspect(model.follow, content="true")
  @debug.debug_inspect(
    model.shown.map(fn(o) { o.lines.length() }),
    content="Some(20)",
  )
  @debug.debug_inspect(model.page, content="3")
}

///|
test "a prompt is sent only from the last confirmation page" {
  let model = ready()
  model.update(Gesture(Tap)) |> ignore
  model.update(Draft("x".repeat(BODY_COLUMNS * 6))) |> ignore
  @debug.debug_inspect(model.screen, content="ConfirmPrompt")
  @debug.debug_inspect(model.update(Gesture(Tap)), content="[]")
  @debug.debug_inspect(model.draft_page, content="1")
  let effects = model.update(Gesture(Tap))
  @debug.debug_inspect(effects.length(), content="1")
  @debug.debug_inspect(effects[0] is SendPrompt("a", _), content="true")
  @debug.debug_inspect(model.screen, content="Sending")
  model.update(Gesture(Tap)) |> ignore
  @debug.debug_inspect(model.screen, content="Sending")
  model.update(ActionDone({ accepted: true, message: "ok", request_id: None, }))
  |> ignore
  @debug.debug_inspect(
    model.frame().body,
    content=(
      #|"ok"
    ),
  )
  @debug.debug_inspect(
    model.update(Gesture(Tap)),
    content="[LoadOutput(3, \"a\")]",
  )
}

///|
test "stop requires confirmation and double tap cancels" {
  let model = ready()
  model.update(Gesture(Tap)) |> ignore
  model.update(Gesture(Tap)) |> ignore
  @debug.debug_inspect(model.screen, content="Menu")
  let items = model.menu_items()
  model.menu = items.search(Stop).unwrap()
  model.update(Gesture(Tap)) |> ignore
  @debug.debug_inspect(model.screen, content="ConfirmStop")
  model.update(Gesture(DoubleTap)) |> ignore
  @debug.debug_inspect(model.screen, content="Reading")
  model.update(Gesture(Tap)) |> ignore
  model.menu = items.search(Stop).unwrap()
  model.update(Gesture(Tap)) |> ignore
  @debug.debug_inspect(model.update(Gesture(Tap)), content="[SendStop(\"a\")]")
}

///|
test "voice: hold records, release transcribes, cancel ignores late text" {
  let model = ready()
  model.update(Gesture(Tap)) |> ignore
  @debug.debug_inspect(
    model.update(Gesture(Hold)),
    content="[StartRecording(2)]",
  )
  @debug.debug_inspect(
    model.update(Gesture(Release)),
    content="[FinishRecording(2)]",
  )
  model.update(Transcribed(2, "テストを直して")) |> ignore
  @debug.debug_inspect(model.screen, content="ConfirmPrompt")
  model.update(Gesture(DoubleTap)) |> ignore
  model.update(Gesture(Hold)) |> ignore
  @debug.debug_inspect(
    model.update(Gesture(DoubleTap)),
    content="[CancelRecording, LoadOutput(3, \"a\")]",
  )
  @debug.debug_inspect(model.update(Transcribed(2, "late")), content="[]")
  @debug.debug_inspect(model.screen, content="Reading")
}

///|
test "unauthorized responses return to setup" {
  let model = ready()
  model.update(Gesture(DoubleTap)) |> ignore
  model.update(
    SessionsFailed(2, api_error(401, "unauthorized", "トークン")),
  )
  |> ignore
  @debug.debug_inspect(model.screen, content="Setup")
  @debug.debug_inspect(model.update(Tick(2)), content="[]")
}

///|
test "offline state is shown, not hidden" {
  let model = ready()
  model.update(Gesture(DoubleTap)) |> ignore
  @debug.debug_inspect(
    model.update(
      SessionsFailed(2, api_error(502, "bridge_unavailable", "切断")),
    ),
    content="[Schedule(2, 8000)]",
  )
  @debug.debug_inspect(
    model.frame().title.contains("[接続切れ]"),
    content="true",
  )
  @debug.debug_inspect(model.update(Tick(2)), content="[LoadSessions(2)]")
}

///|
test "frames stay within the heading budget" {
  let model = ready()
  model.update(
    SessionsLoaded(1, [
      session(
        "a", "とても長いセッションのタイトルがここに入ります。さらに長くなります",
      ),
    ]),
  )
  |> ignore
  model.update(Gesture(Tap)) |> ignore
  model.update(OutputLoaded(2, output("a", ["hello"], 1))) |> ignore
  let frame = model.frame()
  @debug.debug_inspect(
    text_width(frame.title) <= HEADING_COLUMNS,
    content="true",
  )
  @debug.debug_inspect(
    frame.body,
    content=(
      #|"hello"
    ),
  )
}
