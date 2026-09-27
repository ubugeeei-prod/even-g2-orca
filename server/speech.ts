import { AUDIO, TIMING } from '../shared/config.ts';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { bridgeError, isBridgeError } from './errors.ts';

const execute = promisify(execFile);

export const speechAvailable = () =>
  Boolean(process.env.WHISPER_CLI_PATH && process.env.WHISPER_MODEL_PATH);

export async function transcribe(wav: Buffer): Promise<string> {
  if (!speechAvailable())
    throw bridgeError(
      'speech_unavailable',
      'Mac 側で whisper.cpp を設定すると音声入力が使えます。',
      409,
    );
  if (
    wav.length < AUDIO.wavHeaderBytes ||
    wav.toString('ascii', 0, 4) !== 'RIFF' ||
    wav.toString('ascii', 8, 12) !== 'WAVE'
  ) {
    throw bridgeError('invalid_audio', 'WAV 音声を送信してください。', 400);
  }
  const directory = await mkdtemp(join(tmpdir(), 'even-orca-audio-'));
  try {
    const input = join(directory, 'audio.wav');
    const output = join(directory, 'transcript');
    await writeFile(input, wav, { mode: 0o600 });
    await execute(
      process.env.WHISPER_CLI_PATH!,
      [
        '-m',
        process.env.WHISPER_MODEL_PATH!,
        '-f',
        input,
        '-l',
        process.env.WHISPER_LANGUAGE ?? 'ja',
        '-otxt',
        '-of',
        output,
        '-nt',
      ],
      { timeout: TIMING.speechTimeout, maxBuffer: 1024 * 1024 },
    );
    const text = (await readFile(output + '.txt', 'utf8')).trim();
    if (!text)
      throw bridgeError(
        'empty_transcript',
        '音声を認識できませんでした。もう一度録音してください。',
        422,
      );
    return text;
  } catch (error) {
    if (isBridgeError(error)) throw error;
    throw bridgeError(
      'transcription_failed',
      '音声認識に失敗しました。Mac 側の whisper.cpp の設定を確認してください。',
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}
