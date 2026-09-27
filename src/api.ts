import { TIMING } from '../shared/config.ts';
import type {
  ActionReceipt,
  ApiErrorBody,
  BridgeInfo,
  Session,
  SessionOutput,
} from '../shared/protocol.ts';

export interface ConnectionSettings {
  url: string;
  token: string;
}

/** Public transport failure with a stable code, without a class hierarchy. */
export const apiError = (code: string, message: string) =>
  Object.assign(new Error(message), { code });
export type ApiFailure = ReturnType<typeof apiError>;

/** Authenticated API client. Mutations are never automatically retried. */
export function createBridgeApi(settings: ConnectionSettings) {
  async function request<T>(
    path: string,
    init: RequestInit = {},
    timeout: number = TIMING.httpTimeout,
  ): Promise<T> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeout);
    try {
      const headers = new Headers(init.headers);
      headers.set('Authorization', `Bearer ${api.settings.token}`);
      const response = await fetch(`${api.settings.url.replace(/\/$/, '')}${path}`, {
        ...init,
        headers,
        signal: controller.signal,
        credentials: 'omit',
        cache: 'no-store',
        redirect: 'error',
      });
      const result = await response.json();
      if (!response.ok) {
        const error = (result as ApiErrorBody).error;
        throw apiError(error?.code ?? 'api_error', error?.message ?? 'ブリッジに接続できません。');
      }
      return result as T;
    } catch (error) {
      if (error instanceof Error && 'code' in error) throw error;
      throw apiError(
        'connection_failed',
        init.method === 'POST'
          ? '操作結果を確認できません。再送する前に Mac 側を確認してください。'
          : 'Mac のブリッジに接続できません。接続先とネットワークを確認してください。',
      );
    } finally {
      clearTimeout(timer);
    }
  }

  const api = {
    settings,
    info: () => {
      return request<BridgeInfo>('/api/info');
    },
    sessions: async () => {
      return (await request<{ sessions: Session[] }>('/api/sessions')).sessions;
    },
    output: (id: string) => {
      return request<SessionOutput>(`/api/sessions/${encodeURIComponent(id)}/output`);
    },
    action: (id: string, action: 'send' | 'stop', text?: string) => {
      return request<ActionReceipt>(
        `/api/sessions/${encodeURIComponent(id)}/${action}`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ operationId: crypto.randomUUID(), text }),
        },
        TIMING.actionTimeout,
      );
    },
    transcribe: async (wav: Blob) => {
      return (
        await request<{ text: string }>(
          '/api/transcribe',
          { method: 'POST', headers: { 'Content-Type': 'audio/wav' }, body: wav },
          TIMING.speechTimeout + TIMING.httpTimeout,
        )
      ).text;
    },
  };
  return api;
}

export type BridgeApi = ReturnType<typeof createBridgeApi>;

/** Pairing fragments override stale tokens; packages embed only a public origin. */
export function loadSettings(): ConnectionSettings {
  let saved: Partial<ConnectionSettings> = {};
  try {
    saved = JSON.parse(localStorage.getItem('even-orca-connection') ?? '{}');
  } catch {
    /* Recover from old or unavailable storage. */
  }
  const params = new URLSearchParams(location.hash.slice(1));
  const token = params.get('token') ?? saved.token ?? '';
  if (params.has('token')) history.replaceState(null, '', location.pathname + location.search);
  const settings = {
    url: params.has('token')
      ? location.origin
      : (saved.url ??
        import.meta.env.VITE_BRIDGE_ORIGIN ??
        (location.protocol === 'file:' ? '' : location.origin)),
    token,
  };
  saveSettings(settings);
  return settings;
}

/** Persist locally when WebView storage is available, otherwise retain in memory. */
export function saveSettings(settings: ConnectionSettings) {
  try {
    localStorage.setItem('even-orca-connection', JSON.stringify(settings));
  } catch {
    /* Settings still work for this session. */
  }
}
