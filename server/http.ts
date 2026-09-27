import packageInfo from '../package.json' with { type: 'json' };
import { AUDIO, LIMITS, TIMING } from '../shared/config.ts';
import { createServer, type IncomingMessage, type ServerResponse } from 'node:http';
import { timingSafeEqual, createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { resolve, extname, sep } from 'node:path';
import type { OrcaGateway } from './orca.ts';
import { bridgeError, isBridgeError, publicError } from './errors.ts';

interface HttpOptions {
  token: string;
  orca: OrcaGateway;
  publicOrigin?: string;
  allowedOrigins?: string[];
  distPath?: string;
  speechAvailable?: boolean;
  transcribe?: (audio: Buffer) => Promise<string>;
}

const mime: Record<string, string> = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.json': 'application/json',
};

function json(response: ServerResponse, status: number, data: unknown) {
  response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  response.end(JSON.stringify(data));
}

async function body(request: IncomingMessage, max = LIMITS.jsonBodyBytes): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let length = 0;
  for await (const chunk of request) {
    length += chunk.length;
    if (length > max) throw bridgeError('body_too_large', '送信データが大きすぎます。', 413);
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

async function jsonBody(request: IncomingMessage): Promise<Record<string, unknown>> {
  if (!request.headers['content-type']?.startsWith('application/json'))
    throw bridgeError('invalid_content_type', 'JSON を送信してください。', 415);
  try {
    const value: unknown = JSON.parse((await body(request)).toString('utf8'));
    if (!value || typeof value !== 'object' || Array.isArray(value))
      throw new Error('Invalid body');
    return value as Record<string, unknown>;
  } catch (error) {
    if (isBridgeError(error)) throw error;
    throw bridgeError('invalid_json', 'JSON の形式が不正です。', 400);
  }
}

/** Bind a small authenticated API with process-local deduplication and no RPC passthrough. */
export function createBridgeServer(options: HttpOptions) {
  const expected = createHash('sha256').update(options.token).digest();
  const actions = new Map<
    string,
    { fingerprint: string; result: Promise<unknown>; created: number }
  >();
  let speechBusy = false;

  return createServer(async (request, response) => {
    response.setHeader('X-Content-Type-Options', 'nosniff');
    response.setHeader('Referrer-Policy', 'no-referrer');
    response.setHeader('Cache-Control', 'no-store');
    try {
      const url = new URL(request.url ?? '/', 'http://bridge.local');
      if (url.pathname === '/healthz') {
        json(response, 200, { ok: true });
        return;
      }
      if (!url.pathname.startsWith('/api/')) {
        if (request.method !== 'GET' && request.method !== 'HEAD')
          throw bridgeError('method_not_allowed', 'GET を使用してください。', 405);
        const root = resolve(options.distPath ?? 'dist');
        const file = resolve(
          root,
          '.' + decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname),
        );
        if (!file.startsWith(root + sep))
          throw bridgeError('not_found', 'ファイルがありません。', 404);
        let content: Buffer;
        try {
          content = await readFile(file);
        } catch {
          throw bridgeError(
            'not_found',
            'vp build を実行してからブリッジを起動してください。',
            404,
          );
        }
        response.writeHead(200, {
          'Content-Type': mime[extname(file)] ?? 'application/octet-stream',
        });
        response.end(request.method === 'HEAD' ? undefined : content);
        return;
      }

      const origin = request.headers.origin;
      // Local sideloads share this server's origin; packaged builds add an explicit origin.
      const sameOrigin =
        origin === `http://${request.headers.host}` || origin === `https://${request.headers.host}`;
      if (
        origin &&
        !sameOrigin &&
        origin !== options.publicOrigin &&
        !options.allowedOrigins?.includes(origin)
      ) {
        throw bridgeError('origin_denied', 'このアプリの接続元が許可されていません。', 403);
      }
      if (origin) {
        response.setHeader('Access-Control-Allow-Origin', origin);
        response.setHeader('Vary', 'Origin');
        response.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        response.setHeader('Access-Control-Allow-Headers', 'Authorization, Content-Type');
      }
      if (request.method === 'OPTIONS') {
        response.writeHead(204);
        response.end();
        return;
      }
      const supplied = (request.headers.authorization ?? '').replace(/^Bearer /, '');
      if (!supplied || !timingSafeEqual(expected, createHash('sha256').update(supplied).digest())) {
        throw bridgeError('unauthorized', 'ペアリング用トークンを確認してください。', 401);
      }

      if (url.pathname === '/api/info' && request.method === 'GET') {
        const sessions = await options.orca.sessions();
        json(response, 200, {
          version: packageInfo.version,
          runtimeReady: true,
          speechAvailable: options.speechAvailable === true,
          sessionCount: sessions.length,
        });
        return;
      }
      if (url.pathname === '/api/sessions' && request.method === 'GET') {
        json(response, 200, { sessions: await options.orca.sessions() });
        return;
      }
      if (url.pathname === '/api/transcribe' && request.method === 'POST') {
        if (!options.transcribe || !options.speechAvailable)
          throw bridgeError('speech_unavailable', 'Mac 側で音声認識を設定してください。', 409);
        if (speechBusy)
          throw bridgeError('speech_busy', '音声認識中です。少し待ってください。', 409);
        if (request.headers['content-type'] !== 'audio/wav')
          throw bridgeError('invalid_content_type', 'WAV 音声を送信してください。', 415);
        speechBusy = true;
        try {
          json(response, 200, {
            text: await options.transcribe(
              await body(request, AUDIO.maxBytes + AUDIO.wavHeaderBytes),
            ),
          });
        } finally {
          speechBusy = false;
        }
        return;
      }
      const match = url.pathname.match(
        /^\/api\/sessions\/([a-zA-Z0-9_-]{1,128})\/(output|send|stop)$/,
      );
      if (!match) throw bridgeError('not_found', 'API がありません。', 404);
      const id = match[1]!;
      const action = match[2]!;
      if (action === 'output' && request.method === 'GET') {
        json(response, 200, await options.orca.output(id));
        return;
      }
      if (action === 'output' || request.method !== 'POST')
        throw bridgeError('method_not_allowed', '操作には POST を使用してください。', 405);
      const payload = await jsonBody(request);
      if (
        typeof payload.operationId !== 'string' ||
        !/^[a-zA-Z0-9_-]{16,128}$/.test(payload.operationId)
      )
        throw bridgeError('invalid_operation', '操作 ID が不正です。', 400);
      const text = typeof payload.text === 'string' ? payload.text.trim() : '';
      if (
        action === 'send' &&
        (!text || text.length > LIMITS.promptCharacters || /[\x00-\x08\x0b-\x1f\x7f]/.test(text))
      )
        throw bridgeError(
          'invalid_prompt',
          `指示は 1〜${LIMITS.promptCharacters} 文字で入力してください。`,
          400,
        );
      const fingerprint = createHash('sha256')
        .update(JSON.stringify({ id, action, text }))
        .digest('hex');
      // Record the promise before executing, so concurrent retries cannot send twice.
      // Failed/ambiguous mutations are retained too; clients must inspect before a new action.
      const previous = actions.get(payload.operationId);
      if (previous && previous.fingerprint !== fingerprint)
        throw bridgeError('operation_conflict', '同じ操作 ID で別の指示は送れません。', 409);
      if (previous) {
        json(response, 200, await previous.result);
        return;
      }
      for (const [key, entry] of actions)
        if (Date.now() - entry.created > TIMING.operationRetention) actions.delete(key);
      if (actions.size >= LIMITS.operations)
        throw bridgeError(
          'action_limit',
          '操作件数が上限に達しました。明日もう一度お試しください。',
          429,
        );
      const result = action === 'send' ? options.orca.send(id, text) : options.orca.stop(id);
      actions.set(payload.operationId, { fingerprint, result, created: Date.now() });
      json(response, 200, await result);
    } catch (error) {
      const failure = publicError(error);
      if (!response.headersSent)
        json(response, failure.status, { error: { code: failure.code, message: failure.message } });
      else response.end();
    }
  });
}
