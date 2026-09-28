///|
/// Node.js adapters. Modules are resolved with `process.getBuiltinModule`, so
/// the compiled script needs no bundler and works as CommonJS or ESM.
using @js {type Value}

///|
extern "js" fn env(name : String) -> String = "(n) => process.env[n] ?? ''"

///|
extern "js" fn platform() -> String = "() => process.platform"

///|
extern "js" fn home_dir() -> String = "() => process.getBuiltinModule('node:os').homedir()"

///|
extern "js" fn script_dir() -> String =
  #|() => {
  #|  const path = process.getBuiltinModule('node:path');
  #|  return path.dirname(process.argv[1] ?? '.');
  #|}

///|
extern "js" fn join_path(a : String, b : String) -> String = "(a, b) => process.getBuiltinModule('node:path').join(a, b)"

///|
extern "js" fn file_exists(path : String) -> Bool = "(p) => process.getBuiltinModule('node:fs').existsSync(p)"

///|
extern "js" fn exit(code : Int) -> Unit = "(c) => process.exit(c)"

///|
extern "js" fn read_text(
  path : String,
  done : (String) -> Unit,
  failed : () -> Unit,
) -> Unit =
  #|(p, done, failed) => {
  #|  process.getBuiltinModule('node:fs').promises.readFile(p, 'utf8').then(done, () => failed());
  #|}

///|
extern "js" fn read_bytes(
  path : String,
  done : (Bytes) -> Unit,
  failed : () -> Unit,
) -> Unit =
  #|(p, done, failed) => {
  #|  process.getBuiltinModule('node:fs').promises.readFile(p).then(done, () => failed());
  #|}

///|
/// Read the persisted pairing token, creating a random one (0600) if absent.
extern "js" fn load_or_create_token(path : String) -> String =
  #|(p) => {
  #|  const fs = process.getBuiltinModule('node:fs');
  #|  const nodePath = process.getBuiltinModule('node:path');
  #|  try { return fs.readFileSync(p, 'utf8').trim(); } catch {}
  #|  const token = process.getBuiltinModule('node:crypto').randomBytes(24).toString('base64url');
  #|  fs.mkdirSync(nodePath.dirname(p), { recursive: true, mode: 0o700 });
  #|  fs.writeFileSync(p, token + '\n', { mode: 0o600, flag: 'wx' });
  #|  return token;
  #|}

///|
extern "js" fn lan_address() -> String =
  #|() => {
  #|  const nets = process.getBuiltinModule('node:os').networkInterfaces();
  #|  for (const list of Object.values(nets)) {
  #|    for (const net of list ?? []) {
  #|      if (net.family === 'IPv4' && !net.internal) return net.address;
  #|    }
  #|  }
  #|  return '127.0.0.1';
  #|}

///|
/// Print a terminal QR code for the pairing URL when qrencode is available.
extern "js" fn print_pairing_qr(url : String) -> Bool =
  #|(url) => {
  #|  const { spawnSync } = process.getBuiltinModule('node:child_process');
  #|  const result = spawnSync('qrencode', ['-t', 'UTF8', '-m', '2', url], {
  #|    encoding: 'utf8', timeout: 5000, maxBuffer: 1024 * 1024,
  #|  });
  #|  if (result.error || result.status !== 0 || !result.stdout) return false;
  #|  process.stdout.write(result.stdout);
  #|  return true;
  #|}

///|
/// One request/response exchange over Orca's local socket. `on_line` returns
/// true once the exchange is settled; later data and errors are ignored.
extern "js" fn socket_exchange(
  endpoint : String,
  request : String,
  timeout_ms : Int,
  max_bytes : Int,
  on_line : (String) -> Bool,
  failed : (String) -> Unit,
) -> Unit =
  #|(endpoint, request, timeoutMs, maxBytes, onLine, failed) => {
  #|  const net = process.getBuiltinModule('node:net');
  #|  const socket = net.createConnection(endpoint);
  #|  let buffer = '';
  #|  let settled = false;
  #|  const settle = (reason) => {
  #|    if (settled) return;
  #|    settled = true;
  #|    clearTimeout(timer);
  #|    socket.destroy();
  #|    if (reason) failed(reason);
  #|  };
  #|  const timer = setTimeout(() => settle('timeout'), timeoutMs);
  #|  socket.setEncoding('utf8');
  #|  socket.on('connect', () => socket.write(request));
  #|  socket.on('error', () => settle('unavailable'));
  #|  socket.on('close', () => settle('closed'));
  #|  socket.on('data', (chunk) => {
  #|    if (settled) return;
  #|    buffer += chunk;
  #|    if (buffer.length > maxBytes) return settle('too_large');
  #|    let end;
  #|    while (!settled && (end = buffer.indexOf('\n')) >= 0) {
  #|      const line = buffer.slice(0, end);
  #|      buffer = buffer.slice(end + 1);
  #|      if (line.trim() && onLine(line)) settle(null);
  #|    }
  #|  });
  #|}

///|
/// Run a program directly (no shell). `done(ok, stdout)` reports exit status;
/// stdout is kept on failure because a refusal may be printed as JSON.
extern "js" fn run_program(
  program : String,
  args : FixedArray[String],
  timeout_ms : Int,
  done : (Bool, String) -> Unit,
) -> Unit =
  #|(program, args, timeoutMs, done) => {
  #|  const { execFile } = process.getBuiltinModule('node:child_process');
  #|  const [file, argv] = program.endsWith('.js')
  #|    ? [process.execPath, [program, ...args]]
  #|    : [program, args];
  #|  execFile(file, argv, { timeout: timeoutMs, maxBuffer: 4 * 1024 * 1024, windowsHide: true },
  #|    (error, stdout) => done(!error, String(stdout ?? '')));
  #|}

///|
/// A private temporary directory, removed by `remove_dir`.
extern "js" fn make_temp_dir(
  done : (String) -> Unit,
  failed : () -> Unit,
) -> Unit =
  #|(done, failed) => {
  #|  const fs = process.getBuiltinModule('node:fs');
  #|  const os = process.getBuiltinModule('node:os');
  #|  const path = process.getBuiltinModule('node:path');
  #|  fs.promises.mkdtemp(path.join(os.tmpdir(), 'even-g2-orca-')).then(done, () => failed());
  #|}

///|
extern "js" fn write_bytes(
  path : String,
  data : Bytes,
  done : () -> Unit,
  failed : () -> Unit,
) -> Unit =
  #|(p, data, done, failed) => {
  #|  process.getBuiltinModule('node:fs').promises.writeFile(p, data, { mode: 0o600 }).then(() => done(), () => failed());
  #|}

///|
extern "js" fn remove_dir(path : String) -> Unit =
  #|(p) => { process.getBuiltinModule('node:fs').promises.rm(p, { recursive: true, force: true }).catch(() => {}); }

///|
/// Start the HTTP listener. The handler receives the raw request/response.
extern "js" fn serve(
  host : String,
  port : Int,
  handler : (Value, Value) -> Unit,
  ready : () -> Unit,
  failed : (String) -> Unit,
) -> Unit =
  #|(host, port, handler, ready, failed) => {
  #|  const http = process.getBuiltinModule('node:http');
  #|  const server = http.createServer((req, res) => {
  #|    try { handler(req, res); } catch (e) {
  #|      console.error(e);
  #|      if (!res.headersSent) { res.writeHead(500, { 'Content-Type': 'application/json' }); }
  #|      res.end('{"error":{"code":"bridge_error","message":"ブリッジでエラーが発生しました。"}}');
  #|    }
  #|  });
  #|  server.requestTimeout = 150000;
  #|  server.on('error', (e) => failed(String(e && e.code || e)));
  #|  server.listen(port, host, () => ready());
  #|}

///|
extern "js" fn req_method(req : Value) -> String = "(r) => r.method ?? 'GET'"

///|
extern "js" fn req_url(req : Value) -> String = "(r) => r.url ?? '/'"

///|
/// Header value; an absent header reads as "".
extern "js" fn req_header(req : Value, name : String) -> String =
  #|(r, n) => { const v = r.headers[n.toLowerCase()]; return Array.isArray(v) ? v.join(', ') : (v ?? ''); }

///|
/// Collect the body up to `limit` bytes; larger bodies fail with 413.
extern "js" fn read_body(
  req : Value,
  limit : Int,
  done : (Bytes) -> Unit,
  too_large : () -> Unit,
) -> Unit =
  #|(req, limit, done, tooLarge) => {
  #|  const chunks = [];
  #|  let size = 0;
  #|  let over = false;
  #|  req.on('data', (chunk) => {
  #|    if (over) return;
  #|    size += chunk.length;
  #|    if (size > limit) { over = true; tooLarge(); req.resume(); return; }
  #|    chunks.push(chunk);
  #|  });
  #|  req.on('end', () => { if (!over) done(new Uint8Array(Buffer.concat(chunks))); });
  #|  req.on('error', () => { if (!over) { over = true; tooLarge(); } });
  #|}

///|
extern "js" fn utf8_decode(data : Bytes) -> String = "(b) => new TextDecoder().decode(b)"

///|
extern "js" fn respond(
  res : Value,
  status : Int,
  headers : String,
  body : String,
) -> Unit =
  #|(res, status, headers, body) => {
  #|  if (res.writableEnded) return;
  #|  res.writeHead(status, Object.fromEntries(JSON.parse(headers)));
  #|  res.end(status === 204 ? undefined : body);
  #|}

///|
extern "js" fn respond_bytes(
  res : Value,
  status : Int,
  headers : String,
  body : Bytes,
) -> Unit =
  #|(res, status, headers, body) => {
  #|  if (res.writableEnded) return;
  #|  res.writeHead(status, Object.fromEntries(JSON.parse(headers)));
  #|  res.end(body);
  #|}

///|
extern "js" fn on_signal(name : String, f : () -> Unit) -> Unit = "(n, f) => { process.on(n, f) }"
