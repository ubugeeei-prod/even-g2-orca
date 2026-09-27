import { TIMING } from '../shared/config.ts';
import { reduce_reader_json, navigation_json } from '../generated/core.js';
import type { BridgeInfo, Session, SessionOutput } from '../shared/protocol.ts';
import { type BridgeApi, type ConnectionSettings, saveSettings } from './api.ts';
import { clip, outputFrame, paginate, sessionsFrame, type DisplayFrame } from './display.ts';
import { createGlassesDisplay, type Gesture } from './even.ts';

export type View = 'sessions' | 'output' | 'actions' | 'draft' | 'stop' | 'recording';
export const actionLabels = [
  '最新を追従 / 一時停止',
  '進捗を聞く',
  '続きを実行',
  '音声で指示',
  '実行を停止',
  'セッション一覧',
];

/** Effect boundary around the pure MoonBit reader; dependencies are injected for tests. */
export function createController(api: BridgeApi, onChange: () => void) {
  let polling = false;
  let lastList = 0;
  let timer: ReturnType<typeof setTimeout> | undefined;
  let recordingTimer: ReturnType<typeof setTimeout> | undefined;
  let generation = 0;
  let started = false;
  let disposed = false;
  let recordingEnd: 'finish' | 'cancel' | undefined;
  const state = {
    api,
    sessions: [] as Session[],
    selectedId: '',
    selection: 0,
    output: undefined as SessionOutput | undefined,
    newest: undefined as SessionOutput | undefined,
    info: undefined as BridgeInfo | undefined,
    view: 'sessions' as View,
    page: 0,
    following: true,
    connected: false,
    busy: false,
    message: '',
    error: '',
    draft: '',
    draftPage: 0,
    actionSelection: 0,
    glasses: createGlassesDisplay(
      (gesture) => {
        void state.gesture(gesture);
      },
      (message) => {
        state.error = message;
        state.changed();
      },
    ),
    get session() {
      return state.sessions.find((session) => session.id === state.selectedId);
    },
    get pages() {
      return state.output ? paginate(state.output.lines) : ['出力を待っています'];
    },
    get draftPages() {
      return paginate([state.draft]);
    },

    frame(): DisplayFrame {
      if (!state.api.settings.token)
        return {
          title: 'ORCA / 接続待ち',
          body: 'スマートフォンで接続設定を開き\nMac のペアリング用トークンを入力してください',
          footer: 'Orca for Even G2',
        };
      if (!state.connected && state.error)
        return {
          title: 'ORCA / 接続エラー',
          body: clip(state.error, 160),
          footer: 'Mac のブリッジとネットワークを確認',
        };
      if (state.view === 'sessions') return sessionsFrame(state.sessions, state.selection);
      if (state.view === 'actions')
        return {
          title: 'ORCA / 操作',
          body: actionLabels
            .map((label, index) => `${index === state.actionSelection ? '>' : ' '} ${label}`)
            .join('\n'),
          footer: 'Swipe:選択 Tap:決定 Double:戻る',
        };
      if (state.view === 'draft')
        return {
          title: 'ORCA / 指示を確認',
          body: state.draftPages[Math.min(state.draftPage, state.draftPages.length - 1)] ?? '',
          footer: `${state.draftPage + 1}/${state.draftPages.length} Swipe:頁 Tap:${state.draftPage < state.draftPages.length - 1 ? '次頁' : '送信'} Double:取消`,
        };
      if (state.view === 'stop')
        return {
          title: 'ORCA / 停止を確認',
          body: `${clip(state.session?.title ?? '', 50)}\n\nこのセッションの実行を停止しますか？`,
          footer: 'Tap:停止 Double:キャンセル',
        };
      if (state.view === 'recording')
        return {
          title: 'ORCA / 録音中',
          body: `G2 に指示を話してください\n\n最大 ${TIMING.recording / 1_000} 秒・録音後に内容を確認できます`,
          footer: 'Tap:録音終了 Double:キャンセル',
        };
      if (state.session && state.output)
        return outputFrame(state.session, state.output, state.page, state.following);
      return {
        title: 'ORCA / 読み込み中',
        body: state.busy ? '処理中です' : '最新の出力を取得しています',
        footer: 'Double:一覧に戻る',
      };
    },

    changed() {
      if (disposed) return;
      onChange();
      void state.glasses.render(state.frame());
    },

    async configure(settings: ConnectionSettings) {
      if (state.busy || state.view === 'recording') {
        state.error = '操作や録音が終わってから接続先を変更してください。';
        state.changed();
        return;
      }
      generation++;
      state.api.settings = settings;
      saveSettings(settings);
      state.sessions = [];
      state.output = undefined;
      state.newest = undefined;
      state.selectedId = '';
      state.view = 'sessions';
      state.connected = false;
      lastList = 0;
      await state.refresh();
    },

    async refresh() {
      if (disposed || polling || !state.api.settings.token) return;
      polling = true;
      const currentGeneration = generation;
      try {
        if (Date.now() - lastList > TIMING.sessionList) {
          const [sessions, info] = await Promise.all([state.api.sessions(), state.api.info()]);
          if (currentGeneration !== generation) return;
          const hoveredId = state.sessions[state.selection]?.id;
          state.sessions = sessions;
          state.info = info;
          lastList = Date.now();
          state.selection = Math.max(0, Math.min(state.selection, sessions.length - 1));
          const hoveredIndex = sessions.findIndex((session) => session.id === hoveredId);
          if (hoveredIndex >= 0) state.selection = hoveredIndex;
          if (state.selectedId && !state.session) {
            state.selectedId = '';
            state.output = undefined;
            state.view = 'sessions';
          }
        }
        const id = state.selectedId;
        if (id) {
          const output = await state.api.output(id);
          if (currentGeneration !== generation || state.selectedId !== id) return;
          state.newest = output;
          if (state.following || !state.output) {
            state.output = output;
            Object.assign(
              state,
              JSON.parse(
                reduce_reader_json(state.page, state.following, 'arrived', 0, state.pages.length),
              ),
            );
          }
        }
        state.connected = true;
        state.error = '';
      } catch (error) {
        if (currentGeneration === generation) {
          state.connected = false;
          state.error = error instanceof Error ? error.message : '接続エラー';
        }
      } finally {
        polling = false;
        state.changed();
      }
    },

    start() {
      if (started || disposed) return;
      started = true;
      const tick = async () => {
        await state.refresh();
        if (!disposed) timer = setTimeout(tick, state.connected ? TIMING.poll : TIMING.reconnect);
      };
      void tick();
    },

    async open(id: string) {
      if (state.busy || state.view === 'recording') return;
      state.selectedId = id;
      state.selection = Math.max(
        0,
        state.sessions.findIndex((session) => session.id === id),
      );
      state.output = undefined;
      state.newest = undefined;
      state.view = 'output';
      state.following = true;
      state.page = 0;
      state.changed();
      // A previous poll may be in flight; it checks the selected ID before publishing.
      if (!polling) await state.refresh();
    },

    move(direction: number) {
      if (state.view === 'sessions')
        state.selection = Math.max(
          0,
          Math.min(state.sessions.length - 1, state.selection + direction),
        );
      else if (state.view === 'actions')
        state.actionSelection = Math.max(
          0,
          Math.min(actionLabels.length - 1, state.actionSelection + direction),
        );
      else if (state.view === 'output') {
        Object.assign(
          state,
          JSON.parse(
            reduce_reader_json(state.page, state.following, 'move', direction, state.pages.length),
          ),
        );
      }
      state.changed();
    },

    toggleFollow() {
      Object.assign(
        state,
        JSON.parse(
          reduce_reader_json(
            state.page,
            state.following,
            'toggle',
            0,
            state.newest ? paginate(state.newest.lines).length : state.pages.length,
          ),
        ),
      );
      if (state.following && state.newest) {
        state.output = state.newest;
        state.page = state.pages.length - 1;
      }
      state.changed();
    },

    prepareDraft(text: string) {
      state.draft = text;
      state.draftPage = 0;
      state.view = 'draft';
      state.changed();
    },

    async execute(action: 'send' | 'stop') {
      if (state.busy || !state.selectedId || !state.connected) return;
      const id = state.selectedId;
      const text = state.draft.trim();
      if (action === 'send' && !text) return;
      state.busy = true;
      state.error = '';
      state.changed();
      try {
        const result = await state.api.action(id, action, action === 'send' ? text : undefined);
        state.message = result.message;
        if (!result.accepted) state.error = result.message;
        state.view = 'output';
        state.following = true;
        if (result.accepted && action === 'send') state.draft = '';
        await state.refresh();
      } catch (error) {
        state.error = error instanceof Error ? error.message : '操作に失敗しました';
        state.view = 'output';
      } finally {
        state.busy = false;
        state.changed();
      }
    },

    async selectAction(index: number) {
      if (index === 0) {
        state.view = 'output';
        state.toggleFollow();
      }
      if (index === 1) state.prepareDraft('現在の進捗と残りの作業を簡潔に教えてください。');
      if (index === 2) state.prepareDraft('続きの作業を進めてください。');
      if (index === 3) await state.record();
      if (index === 4) {
        state.view = 'stop';
        state.changed();
      }
      if (index === 5) {
        state.view = 'sessions';
        state.changed();
      }
    },

    async record() {
      if (!state.info?.speechAvailable) {
        state.error = '音声入力には Mac 側で whisper.cpp の設定が必要です。';
        state.changed();
        return;
      }
      if (state.busy || !state.selectedId) return;
      state.busy = true;
      state.view = 'recording';
      recordingEnd = undefined;
      state.changed();
      try {
        await state.glasses.startRecording();
        if (disposed || recordingEnd === 'cancel') {
          await state.glasses.cancelRecording();
          state.view = 'output';
          return;
        }
        recordingTimer = setTimeout(() => {
          void state.finishRecording();
        }, TIMING.recording);
      } catch (error) {
        state.error = error instanceof Error ? error.message : '録音を開始できません';
        state.view = 'output';
      } finally {
        state.busy = false;
        state.changed();
      }
      if (recordingEnd === 'finish') await state.finishRecording();
    },

    async finishRecording() {
      if (state.view !== 'recording' || state.busy) return;
      clearTimeout(recordingTimer);
      state.busy = true;
      state.changed();
      try {
        const wav = await state.glasses.stopRecording();
        const transcript = await state.api.transcribe(wav);
        if (!disposed) state.prepareDraft(transcript);
      } catch (error) {
        state.error = error instanceof Error ? error.message : '音声認識に失敗しました';
        state.view = 'output';
      } finally {
        state.busy = false;
        state.changed();
      }
    },

    async gesture(gesture: Gesture) {
      if (state.busy) {
        if (state.view === 'recording') {
          if (gesture === 'back' || gesture === 'cancel') recordingEnd = 'cancel';
          else if (gesture === 'release' || gesture === 'tap') recordingEnd ??= 'finish';
        }
        return;
      }
      const next: { view: View; selection: number; actionSelection: number; effect: string } =
        JSON.parse(
          navigation_json(
            state.view,
            gesture,
            state.selection,
            state.sessions.length,
            state.actionSelection,
            actionLabels.length,
          ),
        );
      state.view = next.view;
      state.selection = next.selection;
      state.actionSelection = next.actionSelection;
      switch (next.effect) {
        case 'draft-up':
        case 'draft-down':
          state.draftPage = Math.max(
            0,
            Math.min(
              state.draftPages.length - 1,
              state.draftPage + (next.effect === 'draft-up' ? -1 : 1),
            ),
          );
          break;
        case 'page-up':
          state.move(-1);
          break;
        case 'page-down':
          state.move(1);
          break;
        case 'open': {
          const session = state.sessions[state.selection];
          if (session) await state.open(session.id);
          break;
        }
        case 'refresh':
          lastList = 0;
          await state.refresh();
          break;
        case 'action':
          await state.selectAction(state.actionSelection);
          break;
        case 'send':
          if (state.draftPage < state.draftPages.length - 1) state.draftPage++;
          else await state.execute('send');
          break;
        case 'stop':
          await state.execute('stop');
          break;
        case 'record':
          await state.record();
          break;
        case 'finish-recording':
          state.view = 'recording';
          await state.finishRecording();
          break;
        case 'cancel-recording':
          clearTimeout(recordingTimer);
          await state.glasses.cancelRecording();
          break;
      }
      state.changed();
    },

    dispose() {
      disposed = true;
      generation++;
      clearTimeout(timer);
      clearTimeout(recordingTimer);
      state.glasses.dispose();
    },
  };
  return state;
}
