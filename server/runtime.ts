import { LIMITS, TIMING } from '../shared/config.ts';
import { readFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import { join } from 'node:path';
import { createConnection } from 'node:net';
import { randomUUID } from 'node:crypto';
import { bridgeError } from './errors.ts';

interface RuntimeMetadata {
  authToken: string;
  runtimeId: string;
  transports: { kind: string; endpoint: string }[];
}

export type RuntimeCall = <T>(method: string, params: Record<string, unknown>) => Promise<T>;

/** Resolve the installed app's platform-specific profile, allowing an explicit override. */
export function defaultUserDataPath(): string {
  if (process.env.ORCA_USER_DATA_PATH) return process.env.ORCA_USER_DATA_PATH;
  if (process.platform === 'darwin') return join(homedir(), 'Library/Application Support/orca');
  if (process.platform === 'win32') return join(process.env.APPDATA ?? homedir(), 'orca');
  return join(process.env.XDG_CONFIG_HOME ?? join(homedir(), '.config'), 'orca');
}

/** Call Orca's local authenticated socket; runtime credentials stay in this process. */
export function createRuntimeCall(userDataPath = defaultUserDataPath()): RuntimeCall {
  return async <T>(method: string, params: Record<string, unknown>): Promise<T> => {
    let metadata: RuntimeMetadata;
    try {
      metadata = JSON.parse(await readFile(join(userDataPath, 'orca-runtime.json'), 'utf8'));
    } catch {
      throw bridgeError('orca_unavailable', 'Mac で Orca を起動してください。', 503);
    }
    const transport = metadata.transports?.find(
      (item) => item.kind === 'unix' || item.kind === 'named-pipe',
    );
    if (!transport?.endpoint || !metadata.authToken) {
      throw bridgeError('orca_incompatible', 'Orca のローカル接続情報を読み取れません。', 503);
    }
    return new Promise<T>((resolve, reject) => {
      const id = randomUUID();
      const socket = createConnection(transport.endpoint);
      let buffer = '';
      let settled = false;
      const finish = (error?: Error, result?: T) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        socket.destroy();
        if (error) reject(error);
        else resolve(result as T);
      };
      const timer = setTimeout(
        () => finish(bridgeError('orca_timeout', 'Orca からの応答がタイムアウトしました。', 504)),
        TIMING.runtimeTimeout,
      );
      socket.setEncoding('utf8');
      socket.on('connect', () =>
        socket.write(JSON.stringify({ id, authToken: metadata.authToken, method, params }) + '\n'),
      );
      socket.on('error', () =>
        finish(bridgeError('orca_unavailable', 'Orca に接続できません。', 503)),
      );
      socket.on('close', () =>
        finish(bridgeError('orca_disconnected', 'Orca との接続が閉じられました。', 503)),
      );
      socket.on('data', (chunk: string) => {
        buffer += chunk;
        if (Buffer.byteLength(buffer) > LIMITS.runtimeBytes) {
          finish(bridgeError('orca_response_too_large', 'Orca の応答が大きすぎます。'));
          return;
        }
        let end: number;
        while ((end = buffer.indexOf('\n')) >= 0 && !settled) {
          const line = buffer.slice(0, end);
          buffer = buffer.slice(end + 1);
          if (!line.trim()) continue;
          try {
            const frame = JSON.parse(line);
            if (frame._keepalive === true) continue;
            if (
              frame.id !== id ||
              (frame._meta?.runtimeId && frame._meta.runtimeId !== metadata.runtimeId)
            ) {
              throw new Error('Mismatched runtime response');
            }
            if (frame.ok === false) {
              finish(
                bridgeError(
                  frame.error?.code ?? 'orca_error',
                  'Orca が操作を受け付けませんでした。Mac 側で状態を確認してください。',
                ),
              );
            } else if (frame.ok === true && frame.result !== undefined) {
              finish(undefined, frame.result as T);
            } else throw new Error('Invalid response');
          } catch {
            finish(bridgeError('orca_invalid_response', 'Orca の応答形式に対応していません。'));
          }
        }
      });
    });
  };
}
