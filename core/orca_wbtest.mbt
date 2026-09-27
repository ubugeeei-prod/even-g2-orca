///|
let list_fixture : String =
  #|{"terminals":[
  #| {"handle":"term_shell","title":"Terminal 1","worktreePath":"/w/app","branch":"refs/heads/main","connected":true,"writable":true,"lastOutputAt":300},
  #| {"handle":"term_old","agentIdentity":"claude","title":"\u001b[1mOld\u001b[0m","worktreePath":"/w/app","branch":"refs/heads/feat/x","connected":true,"writable":true,"lastOutputAt":100,"preview":"line 1\nlast line   \n"},
  #| {"handle":"term_new","agentIdentity":"codex","title":"New","worktreePath":"/w/api/","branch":"main","connected":true,"writable":false,"lastOutputAt":200},
  #| {"handle":"term_gone","agentIdentity":"claude","orphaned":true}
  #|]}

///|
test "sessions_from_list keeps live agents, newest first" {
  let sessions = sessions_from_list(parse_json(list_fixture).unwrap()).unwrap()
  json_inspect(sessions_to_json(sessions), content={
    "sessions": [
      {
        "id": "term_new",
        "title": "New",
        "project": "api",
        "branch": "main",
        "agent": "codex",
        "connected": true,
        "writable": false,
        "updatedAt": 200,
        "preview": "",
      },
      {
        "id": "term_old",
        "title": "Old",
        "project": "app",
        "branch": "feat/x",
        "agent": "claude",
        "connected": true,
        "writable": true,
        "updatedAt": 100,
        "preview": "last line",
      },
    ],
  })
}

///|
test "output_from_read maps agent status conservatively" {
  let read = parse_json(
    "{\"terminal\":{\"status\":\"running\",\"source\":\"screen\",\"tail\":[\"\\u001b[31m> hi  \",\"\",\"\"]}}",
  ).unwrap()
  let status = fn(s : String) {
    parse_json(
      "{\"agentStatus\":{\"isRunningAgent\":true,\"status\":\"" + s + "\"}}",
    ).unwrap()
  }
  let out = output_from_read("t", read, status("working"), 5.0).unwrap()
  json_inspect(out.lines, content=["> hi"])
  @debug.debug_inspect(
    out.state.wire(),
    content=(
      #|"working"
    ),
  )
  @debug.debug_inspect(
    out.source,
    content=(
      #|"screen"
    ),
  )
  @debug.debug_inspect(
    output_from_read("t", read, status("permission"), 0).unwrap().state.wire(),
    content=(
      #|"waiting"
    ),
  )
  @debug.debug_inspect(
    output_from_read("t", read, status("mystery"), 0).unwrap().state.wire(),
    content=(
      #|"unknown"
    ),
  )
  let shell = parse_json("{\"agentStatus\":{\"isRunningAgent\":false}}").unwrap()
  @debug.debug_inspect(
    output_from_read("t", read, shell, 0).unwrap().state.wire(),
    content=(
      #|"idle"
    ),
  )
  let exited = parse_json("{\"terminal\":{\"status\":\"exited\",\"tail\":[]}}").unwrap()
  @debug.debug_inspect(
    output_from_read("t", exited, status("working"), 0).unwrap().state.wire(),
    content=(
      #|"offline"
    ),
  )
  @debug.debug_inspect(
    output_from_read("t", parse_json("{\"terminal\":{}}").unwrap(), shell, 0).unwrap_err().code,
    content=(
      #|"unsupported_session"
    ),
  )
}

///|
test "runtime_endpoint prefers the local socket" {
  let meta =
    #|{"runtimeId":"r1","authToken":"secret","transports":[{"kind":"websocket","endpoint":"ws://0.0.0.0:1"},{"kind":"unix","endpoint":"/tmp/o.sock"}]}
  let endpoint = runtime_endpoint(meta).unwrap()
  @debug.debug_inspect(
    endpoint.endpoint,
    content=(
      #|"/tmp/o.sock"
    ),
  )
  @debug.debug_inspect(
    endpoint.runtime_id,
    content=(
      #|"r1"
    ),
  )
  @debug.debug_inspect(
    runtime_endpoint(
      "{\"authToken\":\"x\",\"transports\":[{\"kind\":\"websocket\",\"endpoint\":\"ws://x\"}]}",
    ).unwrap_err().code,
    content=(
      #|"orca_incompatible"
    ),
  )
  @debug.debug_inspect(
    runtime_endpoint("nope").unwrap_err().code,
    content=(
      #|"orca_incompatible"
    ),
  )
}

///|
test "rpc_frame rejects foreign frames" {
  @debug.debug_inspect(
    rpc_frame("{\"_keepalive\":true}", "a", "r") == Keepalive,
    content="true",
  )
  @debug.debug_inspect(
    rpc_frame(
      "{\"id\":\"a\",\"ok\":true,\"result\":{\"x\":1},\"_meta\":{\"runtimeId\":\"r\"}}",
      "a", "r",
    ) ==
    Done({ "x": 1 }),
    content="true",
  )
  let other = rpc_frame("{\"id\":\"b\",\"ok\":true,\"result\":{}}", "a", "r")
  @debug.debug_inspect(
    other is Failed({ code: "orca_invalid_response", .. }),
    content="true",
  )
  let runtime = rpc_frame(
    "{\"id\":\"a\",\"ok\":true,\"result\":{},\"_meta\":{\"runtimeId\":\"z\"}}", "a",
    "r",
  )
  @debug.debug_inspect(
    runtime is Failed({ code: "orca_invalid_response", .. }),
    content="true",
  )
  let refused = rpc_frame(
    "{\"id\":\"a\",\"ok\":false,\"error\":{\"code\":\"terminal_not_found\"}}", "a",
    "r",
  )
  @debug.debug_inspect(
    refused is Failed({ code: "terminal_not_found", .. }),
    content="true",
  )
  @debug.debug_inspect(
    rpc_request("a", "tok", "terminal.list", {}),
    content=(
      #|"{\"id\":\"a\",\"authToken\":\"tok\",\"method\":\"terminal.list\",\"params\":{}}\n"
    ),
  )
}

///|
test "receipts distinguish acceptance from observed execution" {
  let receipt = fn(json : String, interrupt : Bool) {
    receipt_from_send(parse_json(json).unwrap(), interrupt).unwrap()
  }
  @debug.debug_inspect(
    receipt(
      "{\"send\":{\"accepted\":true,\"prompt\":{\"requestId\":\"q\",\"stages\":[\"accepted\",\"turn_started\"]}}}",
      false,
    ).message,
    content=(
      #|"指示を送信し、実行開始を確認しました。"
    ),
  )
  let queued = receipt(
    "{\"send\":{\"accepted\":true,\"prompt\":{\"stages\":[\"accepted\"]}}}", false,
  )
  @debug.debug_inspect(queued.accepted, content="true")
  @debug.debug_inspect(queued.message.contains("未確認"), content="true")
  @debug.debug_inspect(
    receipt("{\"send\":{\"accepted\":false}}", false).accepted,
    content="false",
  )
  @debug.debug_inspect(
    receipt("{\"send\":{\"accepted\":true}}", true).message.contains("停止"),
    content="true",
  )
  @debug.debug_inspect(
    receipt_from_send({}, false).unwrap_err().code,
    content=(
      #|"delivery_unknown"
    ),
  )
}

///|
test "cli_result reads the JSON envelope" {
  @debug.debug_inspect(
    cli_result("{\"ok\":true,\"result\":{\"a\":1}}") == Ok({ "a": 1 }),
    content="true",
  )
  @debug.debug_inspect(
    cli_result("{\"ok\":false,\"error\":{\"code\":\"not_writable\"}}").unwrap_err().code,
    content=(
      #|"not_writable"
    ),
  )
  @debug.debug_inspect(
    cli_result("garbage").unwrap_err().code,
    content=(
      #|"delivery_unknown"
    ),
  )
}

///|
test "prompt arguments never pass through a shell" {
  json_inspect(send_args("t", "a; rm -rf /"), content=[
    "terminal", "send", "--terminal", "t", "--text", "a; rm -rf /", "--enter", "--wait-submit",
    "2", "--json",
  ])
  @debug.debug_inspect(
    interrupt_args("t").contains("--interrupt"),
    content="true",
  )
}
