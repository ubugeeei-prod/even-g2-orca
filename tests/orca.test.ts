import { expect, test, vi } from 'vite-plus/test';
import { createOrcaGateway } from '../server/orca.ts';
import type { RuntimeCall } from '../server/runtime.ts';

test('requires a currently running agent before any terminal input', async () => {
  const rpc = vi.fn(async () => ({ agentStatus: { isRunningAgent: false } })) as RuntimeCall;
  const cli = vi.fn();
  const orca = createOrcaGateway(rpc, cli);
  await expect(orca.send('term_test', 'rm -rf anything')).rejects.toMatchObject({
    code: 'not_an_agent',
  });
  await expect(orca.stop('term_test')).rejects.toMatchObject({ code: 'not_an_agent' });
  expect(cli).not.toHaveBeenCalled();
});

test('preserves exact prompt text as an argument and reports unobserved delivery', async () => {
  const rpc = vi.fn(async () => ({ agentStatus: { isRunningAgent: true } })) as RuntimeCall;
  const cli = vi.fn(async (_args: string[]) => ({
    send: {
      accepted: true,
      prompt: { requestId: 'receipt', observation: 'pending', stages: ['input_accepted'] },
    },
  }));
  const orca = createOrcaGateway(rpc, cli);
  const text = '日本語の指示\n`echo hidden` $(touch /tmp/no)';
  const result = await orca.send('term_test', text);
  expect(cli.mock.calls[0]?.[0]).toEqual([
    'terminal',
    'send',
    '--terminal',
    'term_test',
    '--text',
    text,
    '--enter',
    '--wait-submit',
    '2',
  ]);
  expect(result).toMatchObject({ accepted: true, requestId: 'receipt', observation: 'pending' });
  expect(result.message).toContain('未確認');
});

test('filters shells and orphaned sessions and orders by recent activity', async () => {
  const rpc = vi.fn(async () => ({
    terminals: [
      { handle: 'shell', title: 'Shell', connected: true },
      { handle: 'orphan', agentIdentity: 'claude', orphaned: true },
      {
        handle: 'old',
        agentIdentity: 'claude',
        lastOutputAt: 10,
        worktreePath: '/repo/foo',
        branch: 'refs/heads/main',
      },
      { handle: 'recent', agentIdentity: 'codex', lastOutputAt: 20 },
    ],
  })) as RuntimeCall;
  const sessions = await createOrcaGateway(rpc, vi.fn()).sessions();
  expect(sessions.map((session) => session.id)).toEqual(['recent', 'old']);
  expect(sessions[1]).toMatchObject({ project: 'foo', branch: 'main' });
});

test('labels unavailable screen output as history without inventing agent status', async () => {
  const rpc: RuntimeCall = vi.fn(async (method: string) =>
    method === 'terminal.read'
      ? {
          terminal: {
            tail: ['\u001b[32mHello\u001b[0m'],
            source: 'screen-unavailable',
            status: 'running',
          },
        }
      : { agentStatus: { isRunningAgent: true, status: 'new-state' } },
  ) as RuntimeCall;
  const output = await createOrcaGateway(rpc, vi.fn()).output('term_test');
  expect(output).toMatchObject({ lines: ['Hello'], source: 'history', state: 'unknown' });
});
