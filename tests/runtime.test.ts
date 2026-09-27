import { afterEach, expect, test } from 'vite-plus/test';
import { createServer, type Server } from 'node:net';
import { mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRuntimeCall } from '../server/runtime.ts';

const resources: { directory: string; server: Server }[] = [];
afterEach(async () => {
  for (const { directory, server } of resources.splice(0)) {
    await new Promise<void>((resolve) => server.close(() => resolve()));
    await rm(directory, { recursive: true });
  }
});

/** Real socket framing fixture; it owns every temporary file it removes. */
async function fixture(reply: (request: Record<string, unknown>) => string) {
  const directory = await mkdtemp(join(tmpdir(), 'g2-rpc-'));
  const endpoint = join(directory, 'rpc.sock');
  const server = createServer((socket) => {
    socket.setEncoding('utf8');
    socket.once('data', (data) => socket.end(reply(JSON.parse(String(data)))));
  });
  await new Promise<void>((resolve) => server.listen(endpoint, resolve));
  resources.push({ directory, server });
  await writeFile(
    join(directory, 'orca-runtime.json'),
    JSON.stringify({
      runtimeId: 'runtime-test',
      authToken: 'local-private-token',
      transports: [{ kind: 'unix', endpoint }],
    }),
  );
  return createRuntimeCall(directory);
}

test('local RPC sends runtime authentication and ignores keepalive frames', async () => {
  const rpc = await fixture((request) => {
    expect(request.authToken).toBe('local-private-token');
    expect(request.method).toBe('terminal.list');
    return (
      JSON.stringify({ _keepalive: true }) +
      '\n' +
      JSON.stringify({
        id: request.id,
        ok: true,
        _meta: { runtimeId: 'runtime-test' },
        result: { terminals: [] },
      }) +
      '\n'
    );
  });
  expect(await rpc('terminal.list', {})).toEqual({ terminals: [] });
});

test('a mismatched runtime cannot publish a stale result', async () => {
  const rpc = await fixture(
    (request) =>
      JSON.stringify({
        id: request.id,
        ok: true,
        _meta: { runtimeId: 'another-runtime' },
        result: { terminals: [] },
      }) + '\n',
  );
  await expect(rpc('terminal.list', {})).rejects.toMatchObject({ code: 'orca_invalid_response' });
});

test('closed or malformed connections fail without exposing local credentials', async () => {
  for (const response of ['', 'invalid-json\n']) {
    const rpc = await fixture(() => response);
    await expect(rpc('terminal.list', {})).rejects.toThrow(/Orca/);
  }
});
