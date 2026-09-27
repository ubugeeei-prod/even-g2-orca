// --- DOM -------------------------------------------------------------------

///|
extern "js" fn set_text(id : String, text : String) -> Unit =
  #|(id, text) => { const el = document.getElementById(id); if (el && el.textContent !== text) el.textContent = text; }

///|
extern "js" fn set_data(name : String, value : String) -> Unit = "(n, v) => { document.body.dataset[n] = v }"

///|
extern "js" fn input_value(id : String) -> String = "(id) => document.getElementById(id)?.value ?? ''"

///|
extern "js" fn set_input(id : String, value : String) -> Unit =
  #|(id, v) => { const el = document.getElementById(id); if (el) el.value = v; }

///|
extern "js" fn on_click(id : String, f : () -> Unit) -> Unit =
  #|(id, f) => document.getElementById(id)?.addEventListener('click', (e) => { e.preventDefault(); f(); })

///|
/// Press-and-hold on a button, mirroring the G2 long press.
extern "js" fn on_press(
  id : String,
  down : () -> Unit,
  up : () -> Unit,
) -> Unit =
  #|(id, down, up) => {
  #|  const el = document.getElementById(id);
  #|  if (!el) return;
  #|  let pressed = false;
  #|  el.addEventListener('pointerdown', (e) => { e.preventDefault(); pressed = true; el.setPointerCapture?.(e.pointerId); down(); });
  #|  const release = () => { if (pressed) { pressed = false; up(); } };
  #|  el.addEventListener('pointerup', release);
  #|  el.addEventListener('pointercancel', release);
  #|}

///|
/// Arrow keys / Enter / Escape drive the preview when no field has focus.
extern "js" fn on_key(f : (String) -> Unit) -> Unit =
  #|(f) => document.addEventListener('keydown', (e) => {
  #|  const t = e.target;
  #|  if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA')) return;
  #|  if (['ArrowUp', 'ArrowDown', 'Enter', 'Escape', 'Backspace'].includes(e.key)) { e.preventDefault(); f(e.key); }
  #|})

///|
extern "js" fn page_origin() -> String = "() => location.origin"

///|
extern "js" fn page_protocol() -> String = "() => location.protocol"

///|
/// Read and erase the URL fragment so the pairing token leaves no history.
extern "js" fn take_fragment() -> String =
  #|() => {
  #|  const hash = location.hash.slice(1);
  #|  if (hash) history.replaceState(null, '', location.pathname + location.search);
  #|  return hash;
  #|}

///|
extern "js" fn url_decode(s : String) -> String =
  #|(s) => { try { return decodeURIComponent(s.replace(/\+/g, ' ')); } catch { return ''; } }

// --- Storage (per device; failures read as empty) ---------------------------

///|
extern "js" fn storage_get(key : String) -> String =
  #|(k) => { try { return localStorage.getItem(k) ?? ''; } catch { return ''; } }

///|
extern "js" fn storage_set(key : String, value : String) -> Unit =
  #|(k, v) => { try { localStorage.setItem(k, v); } catch {} }

///|
extern "js" fn storage_remove(key : String) -> Unit =
  #|(k) => { try { localStorage.removeItem(k); } catch {} }

// --- HTTP ----------------------------------------------------------------------

///|
/// `done(status, body)`; status 0 means the request never completed.
extern "js" fn http_text(
  http_method : String,
  url : String,
  token : String,
  body : String,
  timeout_ms : Int,
  done : (Int, String) -> Unit,
) -> Unit =
  #|(method, url, token, body, timeoutMs, done) => {
  #|  const controller = new AbortController();
  #|  const timer = setTimeout(() => controller.abort(), timeoutMs);
  #|  const headers = { Authorization: 'Bearer ' + token };
  #|  if (body) headers['Content-Type'] = 'application/json';
  #|  fetch(url, { method, headers, body: body || undefined, signal: controller.signal, cache: 'no-store', credentials: 'omit' })
  #|    .then(async (res) => done(res.status, await res.text()))
  #|    .catch(() => done(0, ''))
  #|    .finally(() => clearTimeout(timer));
  #|}

///|
extern "js" fn http_wav(
  url : String,
  token : String,
  header : Bytes,
  pcm : Bytes,
  timeout_ms : Int,
  done : (Int, String) -> Unit,
) -> Unit =
  #|(url, token, header, pcm, timeoutMs, done) => {
  #|  const controller = new AbortController();
  #|  const timer = setTimeout(() => controller.abort(), timeoutMs);
  #|  fetch(url, {
  #|    method: 'POST',
  #|    headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'audio/wav' },
  #|    body: new Blob([header, pcm], { type: 'audio/wav' }),
  #|    signal: controller.signal, cache: 'no-store', credentials: 'omit',
  #|  })
  #|    .then(async (res) => done(res.status, await res.text()))
  #|    .catch(() => done(0, ''))
  #|    .finally(() => clearTimeout(timer));
  #|}

// --- Even G2 via the official Even Hub SDK --------------------------------------

///|
/// Connect to the glasses and create the three text containers. Gestures are
/// reported as `OsEventTypeList` ordinals. Outside the Even App this fails
/// after a short wait and the page works as a preview.
extern "js" fn g2_connect(
  on_event : (Int) -> Unit,
  done : (Bool, String) -> Unit,
) -> Unit =
  #|(onEvent, done) => {
  #|  const sdk = globalThis.EvenHubSdk;
  #|  const g2 = (globalThis.__orcaG2 ??= { bridge: null, recording: false, chunks: [], size: 0 });
  #|  if (!sdk) return done(false, 'Even Hub SDK を読み込めませんでした。');
  #|  const timeout = new Promise((resolve) => setTimeout(() => resolve(null), 5000));
  #|  Promise.race([sdk.waitForEvenAppBridge(), timeout]).then(async (bridge) => {
  #|    if (!bridge) return done(false, 'Even App の外で開いています（プレビュー）。');
  #|    const text = (containerID, containerName, yPosition, height, isEventCapture, textColor) =>
  #|      new sdk.TextContainerProperty({ containerID, containerName, xPosition: 16, yPosition, width: 544,
  #|        height, paddingLength: 2, content: ' ', isEventCapture, textColor });
  #|    const page = new sdk.CreateStartUpPageContainer({ containerTotalNum: 3, textObject: [
  #|      text(1, 'heading', 4, 36, 0, 3), text(2, 'content', 44, 196, 1, 4), text(3, 'footer', 246, 38, 0, 2)] });
  #|    const result = sdk.StartUpPageCreateResult.normalize(await bridge.createStartUpPageContainer(page));
  #|    if (result !== sdk.StartUpPageCreateResult.success) return done(false, 'G2 に表示できません。Even App から開いてください（ブラウザではプレビューのみ）。');
  #|    g2.bridge = bridge;
  #|    const kind = (v) => v === undefined || v === null ? undefined : typeof v === 'number' ? v : sdk.OsEventTypeList.fromJson(v);
  #|    bridge.onEvenHubEvent((event) => {
  #|      const audio = event.audioEvent;
  #|      if (g2.recording && audio && audio.audioPcm && audio.source !== sdk.AudioInputSource.Phone) {
  #|        const pcm = audio.audioPcm;
  #|        if (g2.size + pcm.length <= 1920000) { g2.chunks.push(new Uint8Array(pcm)); g2.size += pcm.length; }
  #|      }
  #|      // Protobuf omits the zero value, so an input event without a type is a click.
  #|      const type = event.textEvent ? kind(event.textEvent.eventType) ?? 0
  #|        : event.listEvent ? kind(event.listEvent.eventType) ?? 0
  #|        : event.sysEvent ? kind(event.sysEvent.eventType) : undefined;
  #|      if (type !== undefined) onEvent(type);
  #|    });
  #|    done(true, '');
  #|  }, (error) => done(false, 'G2 に接続できません: ' + String(error)));
  #|}

///|
extern "js" fn g2_update(
  id : Int,
  name : String,
  content : String,
  done : (Bool) -> Unit,
) -> Unit =
  #|(containerID, containerName, content, done) => {
  #|  const sdk = globalThis.EvenHubSdk;
  #|  const bridge = globalThis.__orcaG2?.bridge;
  #|  if (!sdk || !bridge) return done(false);
  #|  const text = content || ' ';
  #|  bridge.textContainerUpgrade(new sdk.TextContainerUpgrade({ containerID, containerName, contentOffset: 0, contentLength: text.length, content: text }))
  #|    .then((ok) => done(ok !== false), () => done(false));
  #|}

///|
extern "js" fn g2_record_start(done : (Bool, String) -> Unit) -> Unit =
  #|(done) => {
  #|  const sdk = globalThis.EvenHubSdk;
  #|  const g2 = globalThis.__orcaG2;
  #|  if (!sdk || !g2?.bridge) return done(false, '音声入力には G2 の接続が必要です。');
  #|  g2.chunks = []; g2.size = 0; g2.recording = true;
  #|  g2.bridge.audioControl(true, sdk.AudioInputSource.Glasses).then(
  #|    (ok) => { if (ok) done(true, ''); else { g2.recording = false; done(false, 'G2 マイクを開始できません。権限を確認してください。'); } },
  #|    () => { g2.recording = false; done(false, 'G2 マイクを開始できません。権限を確認してください。'); });
  #|}

///|
extern "js" fn g2_record_finish(
  done : (Bytes) -> Unit,
  failed : (String) -> Unit,
) -> Unit =
  #|(done, failed) => {
  #|  const sdk = globalThis.EvenHubSdk;
  #|  const g2 = globalThis.__orcaG2;
  #|  const collect = () => {
  #|    g2.recording = false;
  #|    const pcm = new Uint8Array(g2.size);
  #|    let offset = 0;
  #|    for (const chunk of g2.chunks) { pcm.set(chunk, offset); offset += chunk.length; }
  #|    g2.chunks = []; g2.size = 0;
  #|    if (pcm.length === 0) failed('音声が届きませんでした。G2 マイクの権限を確認してください。');
  #|    else done(pcm);
  #|  };
  #|  if (!sdk || !g2?.bridge) return failed('G2 との接続が切れました。');
  #|  g2.bridge.audioControl(false, sdk.AudioInputSource.Glasses).then(collect, collect);
  #|}

///|
extern "js" fn g2_record_cancel() -> Unit =
  #|() => {
  #|  const sdk = globalThis.EvenHubSdk;
  #|  const g2 = globalThis.__orcaG2;
  #|  if (!g2) return;
  #|  const wasRecording = g2.recording;
  #|  g2.recording = false; g2.chunks = []; g2.size = 0;
  #|  if (wasRecording && sdk && g2.bridge) g2.bridge.audioControl(false, sdk.AudioInputSource.Glasses).catch(() => {});
  #|}
