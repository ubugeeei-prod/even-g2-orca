///|
/// What the Worker does with a request.
pub(all) enum Relay {
  /// Not an API path: serve static assets.
  Assets
  /// Answer directly with a JSON body.
  Respond(Int, String)
  /// CORS preflight.
  Preflight
  /// Forward to the bridge at this absolute URL.
  Forward(String)
} derive(Eq, Debug)

///|
pub extend Relay with Eq::{not_equal, equal}

///|
pub extend Relay with Debug::{to_repr}

///|
/// The configured bridge origin must be exactly `https://host`.
pub fn normalize_bridge_origin(value : String) -> String? {
  let raw = value.trim().to_owned()
  guard raw.has_prefix("https://") else { return None }
  let chars = raw.to_array()
  let mut end = chars.length()
  if end > 8 && chars[end - 1] == '/' {
    end -= 1
  }
  let host = String::from_array(chars[8:end])
  if host.length() == 0 {
    return None
  }
  for c in host {
    if !(c is ('a'..='z' | 'A'..='Z' | '0'..='9' | '.' | '-' | ':')) {
      return None
    }
  }
  Some("https://" + host)
}

///|
/// Relay only known API routes to one fixed HTTPS origin. Credentials for
/// Cloudflare Access are added by the Worker shell and never leave it.
pub fn relay_plan(
  http_method : String,
  target : String,
  self_origin : String,
  origin : String?,
  authorization : String?,
  bridge_origin : String,
  allowed_origins : String,
  has_access_credentials : Bool,
) -> (Relay, Array[(String, String)]) {
  let path = path_only(target)
  if !is_api_path(path) {
    return (Assets, [])
  }
  let fail = fn(e : ApiError) {
    (Relay::Respond(e.status, e.to_json().stringify()), json_headers())
  }
  if !origin_allowed(origin, self_origin, allowed_origins) {
    return fail(
      api_error(
        403, "origin_denied", "同じアプリから接続してください。",
      ),
    )
  }
  let cors = cors_headers(origin)
  let with_cors = fn(pair : (Relay, Array[(String, String)])) {
    let (relay, headers) = pair
    (relay, headers + cors)
  }
  if http_method == "OPTIONS" {
    return (Preflight, cors)
  }
  match route(http_method, path) {
    Err(e) => return with_cors(fail(e))
    Ok(Asset(_)) => return with_cors(fail(not_found()))
    Ok(_) => ()
  }
  guard authorization is Some(a) && a.has_prefix("Bearer ") else {
    return with_cors(fail(unauthorized()))
  }
  guard normalize_bridge_origin(bridge_origin) is Some(bridge) else {
    return with_cors(
      fail(
        api_error(
          503, "bridge_not_configured", "Cloudflare のブリッジ接続先を設定してください。",
        ),
      ),
    )
  }
  if !has_access_credentials {
    return with_cors(
      fail(
        api_error(
          503, "access_not_configured", "Cloudflare Access の資格情報を設定してください。",
        ),
      ),
    )
  }
  (Forward(bridge + path), json_headers() + cors)
}
