import './style.css';
import { createBridgeApi, loadSettings } from './api.ts';
import { createController } from './controller.ts';
import { stateLabel } from './display.ts';
import { LIMITS, TIMING } from '../shared/config.ts';

const root = document.querySelector<HTMLDivElement>('#app')!;
root.innerHTML = `
  <header class="topbar">
    <a class="brand" href="/" aria-label="Orca for Even G2 ホーム"><span class="brand-icon" aria-hidden="true">◒</span> orca <span class="brand-divider">/</span> <span class="device-label">EVEN G2</span></a>
    <div class="topbar-right"><span id="connection" class="badge"><i></i>未接続</span><button id="settings-open" class="icon-button" aria-label="接続設定">接続設定 <span aria-hidden="true">↗</span></button></div>
  </header>
  <main>
    <section class="intro"><p class="eyebrow">YOUR WORK, IN SIGHT</p><h1>作業の続きを、視線の先に。</h1><p>Orca の進捗と返答を、Even G2 から。</p></section>
    <div id="notice" class="notice" role="status" aria-live="polite" hidden></div>
    <div class="workspace">
      <aside class="sessions-panel">
        <div class="panel-heading"><h2>セッション <span id="session-count">0</span></h2><button id="refresh" class="icon-button" aria-label="セッションを更新">↻</button></div>
        <p class="panel-description">Orca で開いているエージェント</p>
        <div id="session-list" class="session-list"></div>
        <div id="empty-sessions" class="empty"><span aria-hidden="true">◎</span><p>Mac のブリッジに接続して<br>セッションを表示します。</p><button id="empty-connect" class="text-button">接続を設定する →</button></div>
        <div class="sidebar-foot"><span class="tiny-dot"></span> G2 / R1 のタッチで操作</div>
      </aside>
      <section class="display-panel">
        <div class="panel-heading"><h2>グラスの表示</h2><button id="glasses-connect" class="text-button">G2 に接続 ↗</button></div>
        <div class="display-caption"><span id="glasses-status">ブラウザプレビュー</span><span>576 × 288</span></div>
        <div class="glass-screen" role="region" aria-label="Even G2 表示プレビュー">
          <div id="glass-title" class="glass-title"></div><pre id="glass-body" class="glass-body"></pre><div id="glass-footer" class="glass-footer"></div>
        </div>
        <div class="reader-toolbar"><div><span id="state" class="state-pill">セッションを選択</span><span id="updated" class="timestamp"></span></div><button id="follow" class="follow-button" aria-pressed="true">● 最新を追従</button></div>
        <div class="reader-navigation"><button id="previous" aria-label="前のページ">← 前へ</button><span id="page-count">— / —</span><button id="next" aria-label="次のページ">次へ →</button></div>
        <div class="gesture-guide"><div><kbd>SWIPE</kbd><span>ページを移動</span></div><div><kbd>TAP</kbd><span>操作メニュー</span></div><div><kbd>DOUBLE</kbd><span>一覧に戻る</span></div></div>
        <div class="simulator-controls" aria-label="グラス入力を試す"><span>入力を試す</span><button id="gesture-up" aria-label="上にスワイプ">↑</button><button id="gesture-down" aria-label="下にスワイプ">↓</button><button id="gesture-tap">Tap</button><button id="gesture-back">Double</button></div>
      </section>
      <aside class="controls-panel">
        <div class="panel-heading"><h2>セッションの操作</h2><span class="small-label">CONTROL</span></div>
        <p id="selected-title" class="selected-title">セッションを選んでください</p>
        <div class="quick-actions"><button id="ask-progress"><span aria-hidden="true">↗</span> 進捗を聞く</button><button id="continue"><span aria-hidden="true">▷</span> 続きを実行</button></div>
        <form id="prompt-form"><label for="prompt">指示を送る</label><textarea id="prompt" rows="5" maxlength="${LIMITS.promptCharacters}" placeholder="次にしてほしいことを入力…"></textarea><div class="composer-footer"><button id="record" type="button" class="text-button">◎ 音声入力</button><button id="send" type="submit" class="primary-button">内容を確認 →</button></div></form>
        <div id="confirmation" class="confirmation" hidden><p id="confirmation-label"></p><div><button id="cancel-action">キャンセル</button><button id="confirm-action" class="primary-button">送信する</button></div></div>
        <button id="stop" class="stop-button">□ 実行を停止</button>
        <div class="connection-note"><span aria-hidden="true">⌁</span><p>指示は選択したセッションに届きます。<br>音声入力も内容を確認してから送信。</p></div>
      </aside>
    </div>
    <footer class="page-footer"><span>ORCA FOR EVEN G2</span><span id="source-note">Mac の Orca と接続して使うプライベートリモート</span></footer>
  </main>
  <dialog id="settings"><form id="settings-form"><div class="dialog-heading"><div><p class="eyebrow">PAIR YOUR MAC</p><h2>Orca に接続</h2></div><button id="settings-close" type="button" class="icon-button" aria-label="接続設定を閉じる">✕</button></div><p>Mac で <code>vp run bridge</code> を実行し、表示された接続先とトークンを入力してください。</p><label for="bridge-url">ブリッジ URL</label><input id="bridge-url" type="url" required placeholder="https://your-worker.workers.dev" autocomplete="url" /><label for="bridge-token">ペアリング用トークン</label><input id="bridge-token" type="password" required autocomplete="off" placeholder="Mac に表示されたトークン" /><p class="form-help">トークンはこの端末に保存されます。接続先を変更する場合は、Even Hub の許可先も更新してください。</p><button class="primary-button" type="submit">接続する →</button></form></dialog>
`;

const element = <T extends HTMLElement = HTMLElement>(id: string) =>
  document.getElementById(id) as T;
const dialog = element<HTMLDialogElement>('settings');
const prompt = element<HTMLTextAreaElement>('prompt');
const api = createBridgeApi(loadSettings());
let sessionSignature = '';

/** Update text nodes without injecting agent output as HTML or resetting the composer. */
function render() {
  const frame = controller.frame();
  element('glass-title').textContent = frame.title;
  element('glass-body').textContent = frame.body;
  element('glass-footer').textContent = frame.footer;
  element('connection').classList.toggle('online', controller.connected);
  element('connection').replaceChildren(
    Object.assign(document.createElement('i'), {}),
    document.createTextNode(controller.connected ? 'Orca 接続済み' : '未接続'),
  );
  element('session-count').textContent = String(controller.sessions.length);
  const signature = JSON.stringify([
    controller.sessions.map(({ id, title, project, branch, connected }) => ({
      id,
      title,
      project,
      branch,
      connected,
    })),
    controller.selectedId,
  ]);
  if (sessionSignature !== signature) {
    sessionSignature = signature;
    const buttons = controller.sessions.map((session) => {
      const button = document.createElement('button');
      button.className = 'session-card';
      button.classList.toggle('selected', session.id === controller.selectedId);
      button.setAttribute('aria-pressed', String(session.id === controller.selectedId));
      const project = document.createElement('span');
      project.className = 'session-project';
      project.textContent = session.project;
      const title = document.createElement('strong');
      title.textContent = session.title;
      const detail = document.createElement('span');
      detail.className = 'session-detail';
      detail.textContent = `${session.connected ? '●' : '○'} ${session.agent} · ${session.branch || 'workspace'}`;
      button.append(project, title, detail);
      button.addEventListener('click', () => {
        void controller.open(session.id);
      });
      return button;
    });
    element('session-list').replaceChildren(...buttons);
  }
  element('empty-sessions').hidden = controller.sessions.length > 0;
  element('empty-sessions').querySelector('p')!.textContent = controller.connected
    ? 'エージェントセッションがありません。Mac の Orca で開いてください。'
    : 'Mac のブリッジに接続してセッションを表示します。';
  element('selected-title').textContent = controller.session?.title ?? 'セッションを選んでください';
  element('state').textContent =
    !controller.connected && controller.output
      ? '接続切れ · 保存された表示'
      : controller.newest
        ? stateLabel[controller.newest.state]
        : 'セッションを選択';
  element('state').classList.toggle(
    'working',
    controller.newest?.state === 'working' && controller.connected,
  );
  element('updated').textContent = controller.output
    ? `${new Date(controller.output.capturedAt).toLocaleTimeString('ja-JP')} 取得`
    : '';
  element('page-count').textContent = controller.output
    ? `${controller.page + 1} / ${controller.pages.length}`
    : '— / —';
  element('follow').textContent = controller.following ? '● 最新を追従' : 'Ⅱ 閲覧を一時停止';
  element('follow').setAttribute('aria-pressed', String(controller.following));
  element('source-note').textContent =
    controller.output?.source === 'history'
      ? '履歴表示 · 現在の画面を取得できなかったため、直近の出力を表示しています'
      : `Orca のターミナル画面を表示 · ${TIMING.poll / 1_000} 秒ごとに更新`;
  const notice = element('notice');
  notice.hidden = !controller.error && !controller.message;
  notice.textContent = controller.error || controller.message;
  notice.classList.toggle('error', Boolean(controller.error));
  if (prompt.value !== controller.draft) prompt.value = controller.draft;
  const unavailable =
    !controller.session ||
    !controller.connected ||
    controller.busy ||
    controller.view === 'recording';
  for (const id of ['ask-progress', 'continue', 'send', 'stop'])
    element<HTMLButtonElement>(id).disabled = unavailable;
  element<HTMLButtonElement>('record').disabled =
    !controller.session ||
    !controller.connected ||
    !controller.info?.speechAvailable ||
    !controller.glasses.connected ||
    controller.busy;
  element('record').textContent = controller.view === 'recording' ? '■ 録音を終了' : '◎ 音声入力';
  element<HTMLButtonElement>('previous').disabled = !controller.output || controller.page === 0;
  element<HTMLButtonElement>('next').disabled =
    !controller.output || controller.page >= controller.pages.length - 1;
  element('confirmation').hidden = controller.view !== 'draft' && controller.view !== 'stop';
  element('confirmation-label').textContent =
    controller.view === 'stop'
      ? '選択したセッションの実行を停止しますか？'
      : '表示された指示をこのセッションに送信しますか？';
  element('confirm-action').textContent = controller.view === 'stop' ? '停止する' : '送信する';
  element<HTMLButtonElement>('confirm-action').disabled = controller.busy || !controller.connected;
  element('glasses-status').textContent = controller.glasses.connected
    ? 'Even G2 に表示中'
    : 'ブラウザプレビュー';
  element('glasses-connect').textContent = controller.glasses.connected
    ? 'G2 接続済み'
    : 'G2 に接続 ↗';
}

const controller = createController(api, render);
const on = (id: string, callback: () => void) => element(id).addEventListener('click', callback);
const openSettings = () => {
  element<HTMLInputElement>('bridge-url').value = api.settings.url;
  element<HTMLInputElement>('bridge-token').value = api.settings.token;
  dialog.showModal();
};
on('settings-open', openSettings);
on('empty-connect', openSettings);
on('settings-close', () => dialog.close());
element('settings-form').addEventListener('submit', (event) => {
  event.preventDefault();
  const url = new URL(element<HTMLInputElement>('bridge-url').value);
  if (
    !['http:', 'https:'].includes(url.protocol) ||
    url.username ||
    url.password ||
    url.pathname !== '/' ||
    url.search ||
    url.hash
  ) {
    element<HTMLInputElement>('bridge-url').setCustomValidity(
      'HTTP(S) の接続先オリジンを入力してください。',
    );
    element<HTMLInputElement>('bridge-url').reportValidity();
    return;
  }
  dialog.close();
  void controller.configure({
    url: url.origin,
    token: element<HTMLInputElement>('bridge-token').value.trim(),
  });
});
element('bridge-url').addEventListener('input', () =>
  element<HTMLInputElement>('bridge-url').setCustomValidity(''),
);
on('refresh', () => {
  void controller.refresh();
});
on('previous', () => controller.move(-1));
on('next', () => controller.move(1));
on('follow', () => controller.toggleFollow());
on('ask-progress', () => controller.prepareDraft('現在の進捗と残りの作業を簡潔に教えてください。'));
on('continue', () => controller.prepareDraft('続きの作業を進めてください。'));
prompt.addEventListener('input', () => {
  controller.draft = prompt.value;
});
element('prompt-form').addEventListener('submit', (event) => {
  event.preventDefault();
  if (prompt.value.trim()) controller.prepareDraft(prompt.value);
});
on('stop', () => {
  controller.view = 'stop';
  controller.changed();
});
on('confirm-action', () => {
  void controller.execute(controller.view === 'stop' ? 'stop' : 'send');
});
on('cancel-action', () => {
  controller.view = 'output';
  controller.changed();
});
on('record', () => {
  void (controller.view === 'recording' ? controller.finishRecording() : controller.record());
});
for (const gesture of ['up', 'down', 'tap', 'back'] as const)
  on(`gesture-${gesture}`, () => {
    void controller.gesture(gesture);
  });

let connecting = false;
/** The phone UI remains usable when this page is opened outside the Even host. */
async function connectGlasses() {
  if (connecting || controller.glasses.connected) return;
  connecting = true;
  try {
    await controller.glasses.connect(controller.frame());
  } catch (error) {
    controller.error = error instanceof Error ? error.message : 'G2 に接続できません';
  } finally {
    connecting = false;
    controller.changed();
  }
}
on('glasses-connect', () => {
  void connectGlasses();
});
void connectGlasses();
render();
controller.start();
window.addEventListener('pagehide', () => controller.dispose(), { once: true });
