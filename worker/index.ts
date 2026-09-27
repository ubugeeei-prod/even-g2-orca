/** Runtime bindings. Service credentials are Wrangler secrets, never client assets. */
export interface WorkerEnv {
  ASSETS: { fetch(request: Request): Promise<Response> };
  ORCA_BRIDGE_ORIGIN: string;
  ACCESS_CLIENT_ID: string;
  ACCESS_CLIENT_SECRET: string;
  /** Comma-separated package origins; empty means same-origin only. Never use '*'. */
  ALLOWED_ORIGINS?: string;
}

const apiPath =
  /^\/api\/(info|sessions|transcribe|sessions\/[a-zA-Z0-9_-]{1,128}\/(output|send|stop))$/;

/** Relay only known API routes to one configured HTTPS origin; never retry mutations. */
export async function handleRequest(
  request: Request,
  env: WorkerEnv,
  upstream: typeof fetch = fetch,
): Promise<Response> {
  const url = new URL(request.url);
  if (!url.pathname.startsWith('/api/')) return env.ASSETS.fetch(request);
  const headers = new Headers({
    'Cache-Control': 'no-store',
    'Content-Type': 'application/json',
    'X-Content-Type-Options': 'nosniff',
  });
  const fail = (status: number, code: string, message: string) =>
    new Response(JSON.stringify({ error: { code, message } }), { status, headers });
  if (!apiPath.test(url.pathname)) return fail(404, 'not_found', 'API がありません。');
  if (!['GET', 'POST', 'OPTIONS'].includes(request.method))
    return fail(405, 'method_not_allowed', 'このメソッドは使用できません。');
  const origin = request.headers.get('Origin');
  const allowedOrigins = env.ALLOWED_ORIGINS?.split(',').map((value) => value.trim()) ?? [];
  if (origin && origin !== url.origin && !allowedOrigins.includes(origin))
    return fail(403, 'origin_denied', '同じアプリから接続してください。');
  if (origin) {
    headers.set('Access-Control-Allow-Origin', origin);
    headers.set('Vary', 'Origin');
    headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    headers.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  }
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers });
  if (!request.headers.get('Authorization')?.startsWith('Bearer '))
    return fail(401, 'unauthorized', 'ペアリング用トークンを入力してください。');
  let bridge: URL;
  try {
    bridge = new URL(env.ORCA_BRIDGE_ORIGIN);
    if (
      bridge.protocol !== 'https:' ||
      bridge.pathname !== '/' ||
      bridge.search ||
      bridge.hash ||
      bridge.username ||
      bridge.password
    )
      throw new Error('Invalid origin');
  } catch {
    return fail(503, 'bridge_not_configured', 'Cloudflare のブリッジ接続先を設定してください。');
  }
  if (!env.ACCESS_CLIENT_ID || !env.ACCESS_CLIENT_SECRET)
    return fail(
      503,
      'access_not_configured',
      'Cloudflare Access のサービス資格情報を設定してください。',
    );
  const relayHeaders = new Headers();
  for (const name of ['Authorization', 'Content-Type']) {
    const value = request.headers.get(name);
    if (value) relayHeaders.set(name, value);
  }
  relayHeaders.set('CF-Access-Client-ID', env.ACCESS_CLIENT_ID);
  relayHeaders.set('CF-Access-Client-Secret', env.ACCESS_CLIENT_SECRET);
  try {
    const response = await upstream(new URL(url.pathname, bridge), {
      method: request.method,
      headers: relayHeaders,
      body: request.method === 'POST' ? request.body : undefined,
      redirect: 'manual',
    });
    if (response.status >= 300 && response.status < 400)
      return fail(502, 'access_denied', 'Cloudflare Access の設定を確認してください。');
    if (!response.headers.get('Content-Type')?.startsWith('application/json'))
      return fail(502, 'bridge_unavailable', 'Mac のブリッジに接続できません。');
    return new Response(response.body, { status: response.status, headers });
  } catch {
    return fail(
      502,
      'bridge_unavailable',
      'Mac のブリッジに接続できません。操作後の場合は再送前に出力を確認してください。',
    );
  }
}

export default {
  fetch(request: Request, env: WorkerEnv): Promise<Response> {
    return handleRequest(request, env);
  },
};
