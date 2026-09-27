///|
/// Call Orca's local authenticated RPC. The runtime token never leaves this
/// process.
fn rpc(
  config : Config,
  rpc_method : String,
  params : Json,
  k : (Result[Json, @core.ApiError]) -> Unit,
) -> Unit {
  read_text(
    config.runtime_file,
    fn(metadata) {
      match @core.runtime_endpoint(metadata) {
        Err(e) => k(Err(e))
        Ok(runtime) => {
          let id = @js.random_id()
          socket_exchange(
            runtime.endpoint,
            @core.rpc_request(id, runtime.auth_token, rpc_method, params),
            15000,
            4 * 1024 * 1024,
            fn(line) {
              match @core.rpc_frame(line, id, runtime.runtime_id) {
                Keepalive => false
                Done(result) => {
                  k(Ok(result))
                  true
                }
                Failed(e) => {
                  k(Err(e))
                  true
                }
              }
            },
            fn(reason) {
              k(
                Err(
                  match reason {
                    "timeout" =>
                      @core.api_error(
                        504, "orca_timeout", "Orca からの応答がタイムアウトしました。",
                      )
                    "too_large" =>
                      @core.api_error(
                        502, "orca_response_too_large", "Orca の応答が大きすぎます。",
                      )
                    _ => @core.orca_unavailable()
                  },
                ),
              )
            },
          )
        }
      }
    },
    fn() { k(Err(@core.orca_unavailable())) },
  )
}

///|
/// Run `orca ... --json`. A mutation is never retried here.
fn cli(
  config : Config,
  args : Array[String],
  k : (Result[Json, @core.ApiError]) -> Unit,
) -> Unit {
  run_program(config.cli, args, 25000, fn(_ok, stdout) {
    if stdout.trim().is_empty() {
      k(Err(@core.delivery_unknown()))
    } else {
      k(@core.cli_result(stdout))
    }
  })
}

///|
fn list_sessions(
  config : Config,
  k : (Result[Array[@core.Session], @core.ApiError]) -> Unit,
) -> Unit {
  rpc(
    config,
    "terminal.list",
    {
      "limit": Json::number(@core.MAX_TERMINALS.to_double()),
      "includeVisualLayouts": Json::boolean(false),
    },
    fn(result) {
      match result {
        Ok(json) => k(@core.sessions_from_list(json))
        Err(e) => k(Err(e))
      }
    },
  )
}

///|
fn read_output(
  config : Config,
  id : String,
  k : (Result[@core.Output, @core.ApiError]) -> Unit,
) -> Unit {
  rpc(
    config,
    "terminal.read",
    {
      "terminal": Json::string(id),
      "screen": Json::boolean(true),
      "limit": Json::number(@core.MAX_OUTPUT_LINES.to_double()),
    },
    fn(read) {
      match read {
        Err(e) => k(Err(e))
        Ok(read) =>
          rpc(
            config,
            "terminal.agentStatus",
            { "terminal": Json::string(id) },
            fn(status) {
              match status {
                Err(e) => k(Err(e))
                Ok(status) =>
                  k(@core.output_from_read(id, read, status, @js.now()))
              }
            },
          )
      }
    },
  )
}

///|
/// Deliver input only to a running agent, never to a bare shell. The flag
/// passed to `k` tells whether delivery was attempted at all.
fn deliver(
  config : Config,
  id : String,
  args : Array[String],
  interrupt : Bool,
  k : (Result[@core.Receipt, @core.ApiError], Bool) -> Unit,
) -> Unit {
  rpc(config, "terminal.agentStatus", { "terminal": Json::string(id) }, fn(
    status,
  ) {
    match status {
      Err(e) => k(Err(e), false)
      Ok(status) =>
        if !@core.is_running_agent(status) {
          k(Err(@core.not_an_agent()), false)
        } else {
          cli(config, args, fn(result) {
            match result {
              Ok(json) => k(@core.receipt_from_send(json, interrupt), true)
              Err(e) => k(Err(e), true)
            }
          })
        }
    }
  })
}

///|
/// Recognize speech with a local whisper.cpp; audio never leaves the Mac.
fn transcribe(
  config : Config,
  wav : Bytes,
  k : (Result[String, @core.ApiError]) -> Unit,
) -> Unit {
  let failed = @core.api_error(
    502, "transcription_failed", "音声認識に失敗しました。Mac の whisper.cpp の設定を確認してください。",
  )
  make_temp_dir(
    fn(dir) {
      let input = join_path(dir, "audio.wav")
      let output = join_path(dir, "transcript")
      let finish = fn(result) {
        remove_dir(dir)
        k(result)
      }
      write_bytes(
        input,
        wav,
        fn() {
          run_program(
            config.whisper_cli,
            [
              "-m",
              config.whisper_model,
              "-f",
              input,
              "-l",
              config.whisper_language,
              "-otxt",
              "-of",
              output,
              "-nt",
            ],
            120000,
            fn(ok, _stdout) {
              if !ok {
                finish(Err(failed))
              } else {
                read_text(
                  output + ".txt",
                  fn(text) {
                    let text = text.trim().to_owned()
                    if text.is_empty() {
                      finish(
                        Err(
                          @core.api_error(
                            422, "empty_transcript", "音声を認識できませんでした。もう一度録音してください。",
                          ),
                        ),
                      )
                    } else {
                      finish(Ok(text))
                    }
                  },
                  fn() { finish(Err(failed)) },
                )
              }
            },
          )
        },
        fn() { finish(Err(failed)) },
      )
    },
    fn() { k(Err(failed)) },
  )
}
