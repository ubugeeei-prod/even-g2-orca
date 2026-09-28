///|
using @js {type Value}

///|
/// Register the module's fetch handler; `scripts/assemble.sh` appends the
/// `export default` that Workers require.
extern "js" fn install(
  handler : (Value, Value, (Value) -> Unit) -> Unit,
) -> Unit =
  #|(handler) => {
  #|  globalThis.__orcaFetch = (request, env) =>
  #|    new Promise((resolve) => handler(request, env, resolve));
  #|}

///|
extern "js" fn request_method(request : Value) -> String = "(r) => r.method"

///|
extern "js" fn request_target(request : Value) -> String =
  #|(r) => { const u = new URL(r.url); return u.pathname + u.search }

///|
extern "js" fn request_origin(request : Value) -> String = "(r) => new URL(r.url).origin"

///|
/// Header value; an absent header reads as "".
extern "js" fn request_header(request : Value, name : String) -> String = "(r, n) => r.headers.get(n) ?? ''"

///|
extern "js" fn env_var(env : Value, name : String) -> String =
  #|(env, n) => typeof env[n] === 'string' ? env[n] : ''

///|
extern "js" fn serve_assets(request : Value, env : Value) -> Value =
  #|(r, env) => env.ASSETS ? env.ASSETS.fetch(r) : new Response('Not found', { status: 404 })

///|
extern "js" fn respond(status : Int, headers : String, body : String) -> Value =
  #|(status, headers, body) =>
  #|  new Response(status === 204 ? null : body, { status, headers: new Headers(JSON.parse(headers)) })

///|
/// Forward to the bridge without following redirects (Access would redirect
/// to a login page). The body is streamed for POST.
extern "js" fn forward(
  url : String,
  request : Value,
  headers : String,
  done : (Int, String, Value) -> Unit,
  failed : () -> Unit,
) -> Unit =
  #|(url, r, headers, done, failed) => {
  #|  fetch(url, {
  #|    method: r.method,
  #|    headers: new Headers(JSON.parse(headers)),
  #|    body: r.method === 'POST' ? r.body : undefined,
  #|    redirect: 'manual',
  #|  }).then(
  #|    (res) => done(res.status, res.headers.get('Content-Type') ?? '', res.body),
  #|    () => failed(),
  #|  );
  #|}

///|
extern "js" fn stream_response(
  status : Int,
  headers : String,
  body : Value,
) -> Value =
  #|(status, headers, body) => new Response(body, { status, headers: new Headers(JSON.parse(headers)) })
