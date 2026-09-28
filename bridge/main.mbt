///|
let config : Config = load_config()

///|
let operations : @core.OperationLog = @core.OperationLog::new()

///|
fn send_json(
  res : Value,
  status : Int,
  body : Json,
  cors : Array[(String, String)],
) -> Unit {
  respond(
    res,
    status,
    @js.headers_json(@core.json_headers() + cors),
    body.stringify(),
  )
}

///|
fn send_error(
  res : Value,
  error : @core.ApiError,
  cors : Array[(String, String)],
) -> Unit {
  send_json(res, error.status, error.to_json(), cors)
}

///|
fn too_large() -> @core.ApiError {
  @core.api_error(
    413, "payload_too_large", "送信データが大きすぎます。",
  )
}

///|
/// Run a mutation at most once per operation id and replay its response.
/// Failures before delivery was attempted are not remembered.
fn once(
  res : Value,
  cors : Array[(String, String)],
  id : String,
  fingerprint : String,
  effect : ((Result[Json, @core.ApiError], Bool) -> Unit) -> Unit,
) -> Unit {
  match operations.begin(id, fingerprint, @js.now()) {
    Replay(status, body) =>
      respond(res, status, @js.headers_json(@core.json_headers() + cors), body)
    InFlight =>
      send_error(
        res,
        @core.api_error(
          409, "operation_in_progress", "同じ操作を処理中です。出力を確認してください。",
        ),
        cors,
      )
    Conflict =>
      send_error(
        res,
        @core.api_error(
          409, "operation_conflict", "操作 ID が別の内容で使われています。",
        ),
        cors,
      )
    Fresh =>
      effect(fn(result, attempted) {
        let (status, body) = match result {
          Ok(json) => (200, json)
          Err(e) => (e.status, e.to_json())
        }
        let text = body.stringify()
        if attempted {
          operations.finish(id, status, text)
        } else {
          operations.forget(id)
        }
        respond(
          res,
          status,
          @js.headers_json(@core.json_headers() + cors),
          text,
        )
      })
  }
}

///|
fn serve_asset(res : Value, file : String) -> Unit {
  read_bytes(
    join_path(config.web_root, file),
    fn(data) {
      respond_bytes(
        res,
        200,
        @js.headers_json([
          ("Content-Type", @core.content_type(file)),
          ("Cache-Control", "no-cache"),
          ("X-Content-Type-Options", "nosniff"),
          ("Referrer-Policy", "no-referrer"),
          (
            "Content-Security-Policy", "default-src 'self'; connect-src 'self' https: http:; img-src 'self' data:; object-src 'none'; base-uri 'none'",
          ),
        ]),
        data,
      )
    },
    fn() { send_error(res, @core.not_found(), []) },
  )
}

///|
fn api(
  route : @core.Route,
  req : Value,
  res : Value,
  cors : Array[(String, String)],
) -> Unit {
  let reply = fn(result : Result[Json, @core.ApiError]) {
    match result {
      Ok(json) => send_json(res, 200, json, cors)
      Err(e) => send_error(res, e, cors)
    }
  }
  match route {
    Info =>
      reply(
        Ok(
          @core.BridgeInfo::{
            version,
            speech: config.speech(),
            runtime_ready: file_exists(config.runtime_file),
          }.to_json(),
        ),
      )
    Sessions =>
      list_sessions(config, fn(result) {
        reply(result.map(@core.sessions_to_json))
      })
    Output(id) =>
      read_output(config, id, fn(result) {
        reply(result.map(fn(o) { o.to_json() }))
      })
    Send(id) =>
      read_body(
        req,
        @core.MAX_JSON_BODY_BYTES,
        fn(body) {
          match @core.parse_send_body(utf8_decode(body)) {
            Err(e) => send_error(res, e, cors)
            Ok((op, text)) =>
              once(res, cors, op, "send:\{id}:\{text}", fn(complete) {
                deliver(config, id, @core.send_args(id, text), false, fn(
                  result,
                  attempted,
                ) {
                  complete(result.map(fn(r) { r.to_json() }), attempted)
                })
              })
          }
        },
        fn() { send_error(res, too_large(), cors) },
      )
    Stop(id) =>
      read_body(
        req,
        @core.MAX_JSON_BODY_BYTES,
        fn(body) {
          match @core.parse_stop_body(utf8_decode(body)) {
            Err(e) => send_error(res, e, cors)
            Ok(op) =>
              once(res, cors, op, "stop:\{id}", fn(complete) {
                deliver(config, id, @core.interrupt_args(id), true, fn(
                  result,
                  attempted,
                ) {
                  complete(result.map(fn(r) { r.to_json() }), attempted)
                })
              })
          }
        },
        fn() { send_error(res, too_large(), cors) },
      )
    Transcribe =>
      if !config.speech() {
        send_error(
          res,
          @core.api_error(
            409, "speech_unavailable", "Mac で whisper.cpp を設定すると音声入力が使えます。",
          ),
          cors,
        )
      } else {
        read_body(
          req,
          @core.MAX_AUDIO_BYTES,
          fn(wav) {
            if !@core.looks_like_wav(wav) {
              send_error(
                res,
                @core.api_error(
                  400, "invalid_audio", "WAV 音声を送信してください。",
                ),
                cors,
              )
            } else {
              transcribe(config, wav, fn(result) {
                reply(result.map(fn(text) { { "text": Json::string(text) } }))
              })
            }
          },
          fn() { send_error(res, too_large(), cors) },
        )
      }
    Asset(file) => serve_asset(res, file)
  }
}

///|
fn handle(req : Value, res : Value) -> Unit {
  let http_method = req_method(req)
  let target = req_url(req)
  let path = @core.path_only(target)
  let origin = match req_header(req, "origin") {
    "" => None
    value => Some(value)
  }
  let is_api = @core.is_api_path(path)
  if is_api {
    let self_origin = "http://" + req_header(req, "host")
    if !@core.origin_allowed(origin, self_origin, config.allowed_origins) {
      send_error(
        res,
        @core.api_error(
          403, "origin_denied", "許可されていない接続元です。",
        ),
        [],
      )
      return
    }
    if http_method == "OPTIONS" {
      respond(res, 204, @js.headers_json(@core.cors_headers(origin)), "")
      return
    }
  }
  let cors = if is_api { @core.cors_headers(origin) } else { [] }
  match @core.route(http_method, target) {
    Err(e) => send_error(res, e, cors)
    Ok(Asset(file)) => serve_asset(res, file)
    Ok(route) => {
      let credential = match req_header(req, "authorization") {
        "" => None
        value => Some(value)
      }
      if @core.authorized(credential, config.token) {
        api(route, req, res, cors)
      } else {
        send_error(res, @core.unauthorized(), cors)
      }
    }
  }
}

///|
fn main {
  serve(
    config.host,
    config.port,
    handle,
    fn() {
      let public = if config.public_url != "" {
        config.public_url
      } else if config.host == "0.0.0.0" {
        "http://\{lan_address()}:\{config.port}"
      } else {
        "http://\{config.host}:\{config.port}"
      }
      @js.log("Orca bridge listening on \{config.host}:\{config.port}")
      @js.log("Orca CLI: \{config.cli}")
      @js.log(
        "Speech: " + (if config.speech() { "whisper.cpp" } else { "off" }),
      )
      let pairing_url = "\{public}/#token=\{config.token}"
      @js.log("Pairing URL (grants control; do not share):\n  \{pairing_url}")
      if config.public_url == "" &&
        (
          config.host == "127.0.0.1" ||
          config.host == "localhost" ||
          config.host == "::1"
        ) {
        @js.warn(
          "This address works only on this Mac. For a phone on the same Wi-Fi, restart with BRIDGE_HOST=0.0.0.0 nix run .#bridge.",
        )
      } else if !print_pairing_qr(pairing_url) {
        @js.warn("QR code unavailable; open the pairing URL above.")
      }
    },
    fn(reason) {
      @js.warn("Cannot listen on \{config.host}:\{config.port}: \{reason}")
      exit(1)
    },
  )
  on_signal("SIGINT", fn() { exit(0) })
  on_signal("SIGTERM", fn() { exit(0) })
}
