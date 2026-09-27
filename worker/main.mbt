///|
fn header(request : Value, name : String) -> String? {
  match request_header(request, name) {
    "" => None
    value => Some(value)
  }
}

///|
fn error_response(
  error : @core.ApiError,
  headers : Array[(String, String)],
) -> Value {
  respond(error.status, @js.headers_json(headers), error.to_json().stringify())
}

///|
fn handle(request : Value, env : Value, reply : (Value) -> Unit) -> Unit {
  let access_id = env_var(env, "ACCESS_CLIENT_ID")
  let access_secret = env_var(env, "ACCESS_CLIENT_SECRET")
  let (plan, headers) = @core.relay_plan(
    request_method(request),
    request_target(request),
    request_origin(request),
    header(request, "Origin"),
    header(request, "Authorization"),
    env_var(env, "BRIDGE_ORIGIN"),
    env_var(env, "ALLOWED_ORIGINS"),
    access_id != "" && access_secret != "",
  )
  match plan {
    Assets => reply(serve_assets(request, env))
    Respond(status, body) =>
      reply(respond(status, @js.headers_json(headers), body))
    Preflight => reply(respond(204, @js.headers_json(headers), ""))
    Forward(url) => {
      let upstream : Array[(String, String)] = [
        ("CF-Access-Client-Id", access_id),
        ("CF-Access-Client-Secret", access_secret),
      ]
      for name in ["Authorization", "Content-Type"] {
        if header(request, name) is Some(value) {
          upstream.push((name, value))
        }
      }
      forward(
        url,
        request,
        @js.headers_json(upstream),
        fn(status, content_type, body) {
          if status >= 300 && status < 400 {
            reply(
              error_response(
                @core.api_error(
                  502, "access_denied", "Cloudflare Access の設定を確認してください。",
                ),
                headers,
              ),
            )
          } else if !content_type.has_prefix("application/json") {
            reply(
              error_response(
                @core.api_error(
                  502, "bridge_unavailable", "Mac のブリッジに接続できません。",
                ),
                headers,
              ),
            )
          } else {
            reply(stream_response(status, @js.headers_json(headers), body))
          }
        },
        fn() {
          reply(
            error_response(
              @core.api_error(
                502, "bridge_unavailable", "Mac のブリッジに接続できません。操作後なら再送する前に出力を確認してください。",
              ),
              headers,
            ),
          )
        },
      )
    }
  }
}

///|
fn main {
  install(handle)
}
