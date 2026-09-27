import { expect, test, vi } from 'vite-plus/test';
import {
  validateEvenHubPageContainer,
  AudioInputSource,
  AudioEvent,
  OsEventTypeList,
  StartUpPageCreateResult,
  type EvenHubEvent,
} from '@evenrealities/even_hub_sdk';
import {
  gestureFromEvent,
  pageContainer,
  createGlassesDisplay,
  pcmToWav,
  type EvenBridge,
} from '../src/even.ts';
import { DISPLAY, AUDIO } from '../shared/config.ts';

test('zero-valued click events are recognized from all SDK event sources', () => {
  for (const source of ['textEvent', 'listEvent', 'sysEvent'])
    expect(gestureFromEvent({ [source]: { eventType: 0 } })).toBe('tap');
  expect(gestureFromEvent({ sysEvent: { eventType: OsEventTypeList.SCROLL_BOTTOM_EVENT } })).toBe(
    'down',
  );
  expect(
    gestureFromEvent({ sysEvent: { eventType: OsEventTypeList.IMU_DATA_REPORT } }),
  ).toBeUndefined();
});

test('the official SDK accepts the page and exactly one container captures input', () => {
  const page = pageContainer({ title: 'ORCA', body: '日本語\n出力', footer: '1/3 LIVE' });
  expect(validateEvenHubPageContainer(page)).toMatchObject({ valid: true });
  expect(page.textObject?.filter((container) => container.isEventCapture === 1)).toHaveLength(1);
  for (const container of page.textObject ?? []) {
    expect((container.xPosition ?? 0) + (container.width ?? 0)).toBeLessThanOrEqual(DISPLAY.width);
    expect((container.yPosition ?? 0) + (container.height ?? 0)).toBeLessThanOrEqual(
      DISPLAY.height,
    );
  }
});

test('startup failure does not subscribe to input or enable microphone', async () => {
  const bridge: EvenBridge = {
    createStartUpPageContainer: vi.fn(async () => StartUpPageCreateResult.invalid),
    textContainerUpgrade: vi.fn(),
    onEvenHubEvent: vi.fn(),
    audioControl: vi.fn(),
  };
  const display = createGlassesDisplay(vi.fn(), vi.fn());
  await expect(display.connect({ title: '', body: '', footer: '' }, bridge)).rejects.toThrow();
  expect(display.connected).toBe(false);
  expect(bridge.onEvenHubEvent).not.toHaveBeenCalled();
});

test('microphone bytes form a valid 16 kHz PCM16 mono WAV', async () => {
  const blob = pcmToWav([new Uint8Array([1, 2]), new Uint8Array([3, 4])]);
  const buffer = await blob.arrayBuffer();
  const view = new DataView(buffer);
  expect(new TextDecoder().decode(buffer.slice(0, 4))).toBe('RIFF');
  expect(view.getUint32(24, true)).toBe(AUDIO.sampleRate);
  expect(view.getUint16(22, true)).toBe(1);
  expect(view.getUint32(40, true)).toBe(4);
  expect([...new Uint8Array(buffer).slice(44)]).toEqual([1, 2, 3, 4]);
});

test('disposing a recording always closes the microphone', async () => {
  let listener: (event: EvenHubEvent) => void = () => {};
  const bridge: EvenBridge = {
    createStartUpPageContainer: vi.fn(async () => StartUpPageCreateResult.success),
    textContainerUpgrade: vi.fn(async () => true),
    onEvenHubEvent: vi.fn((callback) => {
      listener = callback;
      return vi.fn();
    }),
    audioControl: vi.fn(async () => true),
  };
  const display = createGlassesDisplay(vi.fn(), vi.fn());
  await display.connect({ title: '', body: '', footer: '' }, bridge);
  await display.startRecording();
  listener({
    audioEvent: new AudioEvent({
      source: AudioInputSource.Glasses,
      audioPcm: new Uint8Array([0, 1]),
    }),
  });
  display.dispose();
  expect(bridge.audioControl).toHaveBeenLastCalledWith(false, 'glasses');
});
