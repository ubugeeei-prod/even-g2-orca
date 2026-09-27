import { afterEach, describe, expect, test, vi } from 'vite-plus/test';
import type { Server } from 'node:http';
import { createBridgeServer } from '../server/http.ts';
import { bridgeError } from '../server/errors.ts';
import type { OrcaGateway } from '../server/orca.ts';

const token = 'test-token-at-least-24-characters';
const servers: Server[] = [];
afterEach(async () => {
  await Promise.all(
    servers
      .splice(0)
      .map((server) => new Promise<void>((resolve) => server.close(() => resolve()))),
  );
});

async function fixture(overrides: Partial<OrcaGateway> = {}) {
  const orca: OrcaGateway = {
    sessions: vi.fn(async () => []),
    output: vi.fn(),
    send: vi.fn(async () => ({ accepted: true, message: 'accepted' })),
    stop: vi.fn(async () => ({ accepted: true, message: 'interrupt sent' })),
    ...overrides,
  };
  const server = createBridgeServer({ token, orca });
  servers.push(server);
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('No port');
  const url = `http://127.0.0.1:${address.port}`;
  const request = (path: string, init: RequestInit = {}) => {
    const headers = new Headers(init.headers);
    headers.set('Authorization', `Bearer ${token}`);
    if (!headers.has('Content-Type')) headers.set('Content-Type', 'application/json');
    return fetch(url + path, { ...init, headers });
  };
  return { orca, url, request };
}

describe('authenticated operation boundary', () => {
  test('rejects unauthenticated access and disallowed browser origins', async () => {
    const { url, request, orca } = await fixture();
    expect((await fetch(url + '/api/sessions')).status).toBe(401);
    expect(
      (await request('/api/sessions', { headers: { Origin: 'https://untrusted.example' } })).status,
    ).toBe(403);
    expect(orca.sessions).not.toHaveBeenCalled();
    expect((await request('/api/sessions', { headers: { Origin: url } })).status).toBe(200);
  });

  test('deduplicates concurrent commands and refuses a changed payload', async () => {
    const send = vi.fn(async () => {
      await new Promise((resolve) => setTimeout(resolve, 20));
      return { accepted: true, message: 'accepted' };
    });
    const { request } = await fixture({ send });
    const body = JSON.stringify({ operationId: 'operation_123456789', text: '進捗を確認して' });
    const responses = await Promise.all([
      request('/api/sessions/term_test/send', { method: 'POST', body }),
      request('/api/sessions/term_test/send', { method: 'POST', body }),
    ]);
    expect(responses.map((response) => response.status)).toEqual([200, 200]);
    expect(send).toHaveBeenCalledTimes(1);
    expect(
      (
        await request('/api/sessions/term_test/send', {
          method: 'POST',
          body: JSON.stringify({ operationId: 'operation_123456789', text: '別の指示' }),
        })
      ).status,
    ).toBe(409);
  });

  test('retains ambiguous failures instead of dispatching a retry', async () => {
    const send = vi.fn(async () => {
      throw bridgeError('delivery_unknown', 'inspect output');
    });
    const { request } = await fixture({ send });
    const init = {
      method: 'POST',
      body: JSON.stringify({ operationId: 'operation_123456789', text: '続けて' }),
    };
    expect((await request('/api/sessions/term_test/send', init)).status).toBe(502);
    expect((await request('/api/sessions/term_test/send', init)).status).toBe(502);
    expect(send).toHaveBeenCalledTimes(1);
  });

  test('rejects control characters, missing IDs and oversized payloads before dispatch', async () => {
    const { request, orca } = await fixture();
    for (const payload of [
      { text: 'hello' },
      { operationId: 'operation_123456789', text: 'hello\u0003' },
      { operationId: 'operation_123456789', text: 'a'.repeat(16001) },
    ]) {
      expect(
        (
          await request('/api/sessions/term_test/send', {
            method: 'POST',
            body: JSON.stringify(payload),
          })
        ).status,
      ).toBe(400);
    }
    expect(
      (
        await request('/api/sessions/term_test/send', {
          method: 'POST',
          body: JSON.stringify({ text: 'a'.repeat(40_000) }),
        })
      ).status,
    ).toBe(413);
    expect(orca.send).not.toHaveBeenCalled();
  });

  test('does not expose raw failures or secrets', async () => {
    const { request } = await fixture({
      sessions: async () => {
        throw new Error('secret-token filesystem-path');
      },
    });
    const response = await request('/api/sessions');
    expect(response.status).toBe(502);
    expect(await response.text()).not.toContain('secret-token');
  });
});
