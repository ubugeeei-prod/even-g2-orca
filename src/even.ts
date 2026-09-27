import { AUDIO, DISPLAY } from '../shared/config.ts';
import {
  waitForEvenAppBridge,
  TextContainerProperty,
  CreateStartUpPageContainer,
  TextContainerUpgrade,
  StartUpPageCreateResult,
  OsEventTypeList,
  AudioInputSource,
  type EvenAppBridge,
} from '@evenrealities/even_hub_sdk';
import type { DisplayFrame } from './display.ts';

export type Gesture = 'up' | 'down' | 'tap' | 'back' | 'hold' | 'release' | 'cancel';
export type EvenBridge = Pick<
  EvenAppBridge,
  'createStartUpPageContainer' | 'textContainerUpgrade' | 'onEvenHubEvent' | 'audioControl'
>;

/** Normalize SDK events, including the zero-valued click event. */
export function gestureFromEvent(event: {
  textEvent?: { eventType?: OsEventTypeList };
  listEvent?: { eventType?: OsEventTypeList };
  sysEvent?: { eventType?: OsEventTypeList };
}): Gesture | undefined {
  const type =
    event.textEvent?.eventType ?? event.listEvent?.eventType ?? event.sysEvent?.eventType;
  switch (type) {
    case OsEventTypeList.CLICK_EVENT:
      return 'tap';
    case OsEventTypeList.DOUBLE_CLICK_EVENT:
      return 'back';
    case OsEventTypeList.SCROLL_TOP_EVENT:
      return 'up';
    case OsEventTypeList.SCROLL_BOTTOM_EVENT:
      return 'down';
    case OsEventTypeList.LONG_PRESS_EVENT:
      return 'hold';
    case OsEventTypeList.LONG_PRESS_RELEASE_EVENT:
      return 'release';
  }
}

/** Use one event-capturing body and separate heading/footer containers. */
export function pageContainer(frame: DisplayFrame) {
  return new CreateStartUpPageContainer({
    containerTotalNum: 3,
    textObject: [
      new TextContainerProperty({
        containerID: 1,
        containerName: 'heading',
        xPosition: DISPLAY.inset,
        yPosition: DISPLAY.heading.y,
        width: DISPLAY.contentWidth,
        height: DISPLAY.heading.height,
        paddingLength: 2,
        content: frame.title,
        isEventCapture: 0,
        textColor: 3,
      }),
      new TextContainerProperty({
        containerID: 2,
        containerName: 'content',
        xPosition: DISPLAY.inset,
        yPosition: DISPLAY.body.y,
        width: DISPLAY.contentWidth,
        height: DISPLAY.body.height,
        paddingLength: 2,
        content: frame.body,
        isEventCapture: 1,
        textColor: 4,
      }),
      new TextContainerProperty({
        containerID: 3,
        containerName: 'footer',
        xPosition: DISPLAY.inset,
        yPosition: DISPLAY.footer.y,
        width: DISPLAY.contentWidth,
        height: DISPLAY.footer.height,
        paddingLength: 2,
        content: frame.footer,
        isEventCapture: 0,
        textColor: 2,
      }),
    ],
  });
}

/** Wrap SDK PCM bytes in a little-endian RIFF/WAVE header. */
export function pcmToWav(chunks: Uint8Array[]): Blob {
  const bytes = chunks.reduce((size, chunk) => size + chunk.byteLength, 0);
  const wav = new Uint8Array(AUDIO.wavHeaderBytes + bytes);
  const view = new DataView(wav.buffer);
  const ascii = (offset: number, value: string) =>
    value.split('').forEach((char, index) => view.setUint8(offset + index, char.charCodeAt(0)));
  ascii(0, 'RIFF');
  view.setUint32(4, 36 + bytes, true);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, AUDIO.sampleRate, true);
  view.setUint32(28, AUDIO.bytesPerSecond, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, AUDIO.bitsPerSample, true);
  ascii(36, 'data');
  view.setUint32(40, bytes, true);
  let offset = AUDIO.wavHeaderBytes;
  for (const chunk of chunks) {
    wav.set(chunk, offset);
    offset += chunk.length;
  }
  return new Blob([wav], { type: 'audio/wav' });
}

/** Serialize display writes and isolate microphone effects from the reader model. */
export function createGlassesDisplay(
  onGesture: (gesture: Gesture) => void,
  onError: (message: string) => void,
) {
  let bridge: EvenBridge | undefined;
  let unsubscribe: (() => void) | undefined;
  let pending: DisplayFrame | undefined;
  let writing = false;
  let last: DisplayFrame | undefined;
  let audio: Uint8Array[] = [];
  let audioSize = 0;
  let recording = false;
  const display = {
    get connected() {
      return Boolean(bridge);
    },

    async connect(frame: DisplayFrame, suppliedBridge?: EvenBridge) {
      if (bridge) return;
      const native = suppliedBridge ?? (await waitForEvenAppBridge());
      const result = await native.createStartUpPageContainer(pageContainer(frame));
      if (result !== StartUpPageCreateResult.success)
        throw new Error('G2 の表示を初期化できません。Even App で接続を確認してください。');
      bridge = native;
      last = frame;
      unsubscribe = native.onEvenHubEvent((event) => {
        if (recording && event.audioEvent?.source === AudioInputSource.Glasses) {
          const pcm = event.audioEvent.audioPcm;
          if (audioSize + pcm.length <= AUDIO.maxBytes) {
            audio.push(new Uint8Array(pcm));
            audioSize += pcm.length;
          }
        }
        if (
          event.sysEvent?.eventType === OsEventTypeList.SYSTEM_EXIT_EVENT ||
          event.sysEvent?.eventType === OsEventTypeList.FOREGROUND_EXIT_EVENT
        ) {
          void display.cancelRecording();
          onGesture('cancel');
        }
        const gesture = gestureFromEvent(event);
        if (gesture) onGesture(gesture);
      });
    },

    async render(frame: DisplayFrame) {
      if (!bridge) return;
      pending = frame;
      if (writing) return;
      writing = true;
      try {
        while (pending && bridge) {
          const next = pending;
          pending = undefined;
          for (const [index, key] of (['title', 'body', 'footer'] as const).entries()) {
            if (next[key] === last?.[key]) continue;
            const success = await bridge.textContainerUpgrade(
              new TextContainerUpgrade({
                containerID: index + 1,
                containerName: ['heading', 'content', 'footer'][index],
                contentOffset: 0,
                contentLength: next[key].length,
                content: next[key],
              }),
            );
            if (!success)
              throw new Error(
                'G2 の表示更新に失敗しました。Even App でアプリを開き直してください。',
              );
          }
          last = next;
        }
      } catch (error) {
        unsubscribe?.();
        void display.cancelRecording();
        bridge = undefined;
        pending = undefined;
        onError(error instanceof Error ? error.message : 'G2 の表示更新に失敗しました。');
      } finally {
        writing = false;
      }
    },

    async startRecording() {
      if (!bridge) throw new Error('音声入力には Even G2 を接続してください。');
      const native = bridge;
      audio = [];
      audioSize = 0;
      recording = true;
      try {
        if (!(await native.audioControl(true, AudioInputSource.Glasses)))
          throw new Error('G2 マイクを開始できません。権限を確認してください。');
        if (bridge !== native || !recording) {
          await native.audioControl(false, AudioInputSource.Glasses);
          throw new Error('録音をキャンセルしました。');
        }
      } catch (error) {
        recording = false;
        throw error;
      }
    },

    async stopRecording(): Promise<Blob> {
      try {
        await bridge?.audioControl(false, AudioInputSource.Glasses);
      } finally {
        recording = false;
      }
      if (!audioSize)
        throw new Error('音声が届きませんでした。G2 マイクの権限を確認してください。');
      const wav = pcmToWav(audio);
      audio = [];
      audioSize = 0;
      return wav;
    },

    async cancelRecording() {
      if (recording) await bridge?.audioControl(false, AudioInputSource.Glasses).catch(() => false);
      recording = false;
      audio = [];
      audioSize = 0;
    },

    dispose() {
      unsubscribe?.();
      void display.cancelRecording();
      bridge = undefined;
    },
  };
  return display;
}
