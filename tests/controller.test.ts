import { afterEach, expect, test, vi } from 'vite-plus/test';
import { createController } from '../src/controller.ts';
import type { BridgeApi } from '../src/api.ts';
import type { Session, SessionOutput } from '../shared/protocol.ts';
import { TIMING } from '../shared/config.ts';

const sessions: Session[] = ['a', 'b'].map((id) => ({
  id,
  title: `Session ${id}`,
  project: 'test',
  branch: 'main',
  agent: 'claude',
  connected: true,
  writable: true,
  updatedAt: null,
  preview: '',
}));
const output = (id: string, offset = 0): SessionOutput => ({
  sessionId: id,
  state: 'working',
  lines: Array.from({ length: 18 }, (_, index) => `line ${offset + index}`),
  source: 'screen',
  truncated: false,
  capturedAt: Date.now(),
});
function fixture(overrides: Partial<BridgeApi> = {}) {
  const api: BridgeApi = {
    settings: { url: 'http://bridge', token: 'token' },
    sessions: vi.fn(async () => sessions),
    info: vi.fn(async () => ({
      version: 'test',
      speechAvailable: false,
      runtimeReady: true,
      sessionCount: sessions.length,
    })),
    output: vi.fn(async (id) => output(id)),
    action: vi.fn(async () => ({ accepted: true, message: 'accepted' })),
    transcribe: vi.fn(),
    ...overrides,
  };
  const controller = createController(api, vi.fn());
  return { api, controller };
}
afterEach(() => vi.useRealTimers());

test('a paused reader preserves the visible snapshot until follow resumes', async () => {
  const { api, controller } = fixture();
  await controller.refresh();
  await controller.open('a');
  controller.move(-1);
  const visible = controller.output;
  vi.mocked(api.output).mockResolvedValue(output('a', 100));
  await controller.refresh();
  expect(controller.output).toBe(visible);
  expect(controller.page).toBe(1);
  controller.toggleFollow();
  expect(controller.output?.lines[0]).toBe('line 100');
  expect(controller.page).toBe(2);
});

test('an in-flight response cannot overwrite a newly selected session', async () => {
  let resolve!: (value: SessionOutput) => void;
  const { controller } = fixture({
    output: vi.fn(
      () =>
        new Promise<SessionOutput>((done) => {
          resolve = done;
        }),
    ),
  });
  await controller.refresh();
  const first = controller.open('a');
  await controller.open('b');
  resolve(output('a'));
  await first;
  expect(controller.selectedId).toBe('b');
  expect(controller.output).toBeUndefined();
});

test('quick prompts and stop require a confirmation tap before dispatch', async () => {
  const { controller, api } = fixture();
  await controller.refresh();
  await controller.open('a');
  await controller.selectAction(1);
  expect(controller.view).toBe('draft');
  expect(api.action).not.toHaveBeenCalled();
  await controller.gesture('back');
  expect(api.action).not.toHaveBeenCalled();
  await controller.selectAction(4);
  expect(controller.view).toBe('stop');
  expect(api.action).not.toHaveBeenCalled();
  await controller.gesture('tap');
  expect(api.action).toHaveBeenCalledExactlyOnceWith('a', 'stop', undefined);
});

test('a disconnected reader labels the failure and keeps the last output', async () => {
  const { controller, api } = fixture();
  await controller.refresh();
  await controller.open('a');
  const visible = controller.output;
  vi.mocked(api.output).mockRejectedValue(new Error('Disconnected'));
  await controller.refresh();
  expect(controller.connected).toBe(false);
  expect(controller.error).toBe('Disconnected');
  expect(controller.output).toBe(visible);
  expect(controller.frame().title).toContain('接続エラー');
});

test('a long draft must reach its final page before a G2 tap can send it', async () => {
  const { controller, api } = fixture();
  await controller.refresh();
  await controller.open('a');
  controller.prepareDraft(
    Array.from({ length: 14 }, (_, index) => `instruction ${index}`).join('\n'),
  );
  expect(controller.draftPages).toHaveLength(3);
  await controller.gesture('tap');
  expect(controller.frame().body).toContain('instruction 6');
  expect(api.action).not.toHaveBeenCalled();
  await controller.gesture('up');
  expect(controller.draftPage).toBe(0);
  await controller.gesture('down');
  await controller.gesture('down');
  expect(controller.frame().body).toContain('instruction 13');
  expect(api.action).not.toHaveBeenCalled();
  await controller.gesture('tap');
  expect(api.action).toHaveBeenCalledTimes(1);
});

test('disposing during polling prevents state publication and rescheduling', async () => {
  vi.useFakeTimers();
  let resolve!: (value: Session[]) => void;
  const { controller, api } = fixture({
    sessions: vi.fn(
      () =>
        new Promise<Session[]>((done) => {
          resolve = done;
        }),
    ),
  });
  controller.start();
  controller.start();
  expect(api.sessions).toHaveBeenCalledTimes(1);
  controller.dispose();
  resolve(sessions);
  await vi.runAllTimersAsync();
  expect(controller.sessions).toEqual([]);
  expect(vi.getTimerCount()).toBe(0);
});

test('list reordering preserves the session under the glasses cursor', async () => {
  vi.useFakeTimers();
  const { controller, api } = fixture();
  await controller.refresh();
  controller.move(1);
  vi.mocked(api.sessions).mockResolvedValue([...sessions].reverse());
  vi.advanceTimersByTime(TIMING.sessionList + 1);
  await controller.refresh();
  expect(controller.sessions[controller.selection]?.id).toBe('b');
});

test('release during microphone startup finishes the recording once', async () => {
  const { controller, api } = fixture();
  await controller.refresh();
  await controller.open('a');
  controller.info!.speechAvailable = true;
  let resolve!: () => void;
  const start = vi.spyOn(controller.glasses, 'startRecording').mockImplementation(
    () =>
      new Promise<void>((done) => {
        resolve = done;
      }),
  );
  const stop = vi.spyOn(controller.glasses, 'stopRecording').mockResolvedValue(new Blob());
  vi.mocked(api.transcribe).mockResolvedValue('音声の指示');
  const recording = controller.record();
  await controller.record();
  await controller.gesture('release');
  resolve();
  await recording;
  expect(start).toHaveBeenCalledTimes(1);
  expect(stop).toHaveBeenCalledTimes(1);
  expect(controller.view).toBe('draft');
  expect(controller.draft).toBe('音声の指示');
  expect(api.action).not.toHaveBeenCalled();
  controller.dispose();
});
