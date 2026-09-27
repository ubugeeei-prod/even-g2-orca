import { expect, test, vi } from 'vite-plus/test';
import { handleRequest, type WorkerEnv } from '../worker/index.ts';

const env: WorkerEnv = {
  ASSETS: { fetch: vi.fn(async () => new Response('asset')) },
  ORCA_BRIDGE_ORIGIN: 'https://bridge.example.com',
  ACCESS_CLIENT_ID: 'service-id',
  ACCESS_CLIENT_SECRET: 'service-secret',
};

test('relays only to the configured origin and discards caller-supplied Access credentials', async () => {
  const upstream = vi.fn(async (_input: RequestInfo | URL, _init?: RequestInit) =>
    Response.json({ sessions: [] }),
  );
  const response = await handleRequest(
    new Request('https://app.example.com/api/sessions?url=https://attacker.example', {
      headers: { Authorization: 'Bearer user-token', 'CF-Access-Client-Secret': 'attacker' },
    }),
    env,
    upstream,
  );
  expect(response.status).toBe(200);
  const [url, init] = upstream.mock.calls[0] ?? [];
  expect(url instanceof URL ? url.href : url).toBe('https://bridge.example.com/api/sessions');
  const headers = new Headers(init?.headers);
  expect(headers.get('CF-Access-Client-Secret')).toBe('service-secret');
  expect(headers.get('Authorization')).toBe('Bearer user-token');
  expect(await response.text()).not.toContain('service-secret');
});

test('never follows Access redirects or forwards unauthorized and unknown routes', async () => {
  const upstream = vi.fn(
    async (_input: RequestInfo | URL, _init?: RequestInit) =>
      new Response(null, { status: 302, headers: { Location: 'https://other.example' } }),
  );
  expect(
    (await handleRequest(new Request('https://app.example.com/api/sessions'), env, upstream))
      .status,
  ).toBe(401);
  expect(
    (await handleRequest(new Request('https://app.example.com/api/rpc'), env, upstream)).status,
  ).toBe(404);
  expect(upstream).not.toHaveBeenCalled();
  expect(
    (
      await handleRequest(
        new Request('https://app.example.com/api/sessions', {
          headers: { Authorization: 'Bearer token' },
        }),
        env,
        upstream,
      )
    ).status,
  ).toBe(502);
  expect(upstream).toHaveBeenCalledTimes(1);
});

test('serves assets even when the Mac bridge is not configured', async () => {
  const response = await handleRequest(new Request('https://app.example.com/'), {
    ...env,
    ORCA_BRIDGE_ORIGIN: '',
  });
  expect(await response.text()).toBe('asset');
});

test('package preflight permits only explicitly configured origins', async () => {
  const upstream = vi.fn();
  const request = new Request('https://app.example.com/api/transcribe', {
    method: 'OPTIONS',
    headers: { Origin: 'https://package.example' },
  });
  expect((await handleRequest(request, env, upstream)).status).toBe(403);
  const response = await handleRequest(
    request,
    { ...env, ALLOWED_ORIGINS: 'https://package.example' },
    upstream,
  );
  expect(response.status).toBe(204);
  expect(response.headers.get('Access-Control-Allow-Origin')).toBe('https://package.example');
  expect(response.headers.get('Access-Control-Allow-Headers')).toContain('Authorization');
  expect(upstream).not.toHaveBeenCalled();
});
