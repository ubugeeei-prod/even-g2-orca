import { LIMITS, TIMING } from '../shared/config.ts';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { access } from 'node:fs/promises';
import { basename } from 'node:path';
import type { ActionReceipt, Session, SessionOutput } from '../shared/protocol.ts';
import { cleanOutput } from '../shared/text.ts';
import { bridgeError, isBridgeError } from './errors.ts';
import type { RuntimeCall } from './runtime.ts';

const execute = promisify(execFile);
const MAC_CLI = '/Applications/Orca.app/Contents/Resources/app.asar.unpacked/out/cli/index.js';

export type CliCall = (args: string[]) => Promise<Record<string, unknown>>;

/** Execute the installed CLI directly with bounded output, without invoking a shell. */
export async function createCliCall(): Promise<CliCall> {
  const configured = process.env.ORCA_CLI_PATH;
  let path = configured ?? 'orca';
  if (!configured && process.platform === 'darwin') {
    try {
      await access(MAC_CLI);
      path = MAC_CLI;
    } catch {
      /* Use the user's PATH. */
    }
  }
  return async (args) => {
    let stdout: string;
    try {
      const result = await execute(
        path.endsWith('.js') ? process.execPath : path,
        [...(path.endsWith('.js') ? [path] : []), ...args, '--json'],
        { timeout: TIMING.cliTimeout, maxBuffer: LIMITS.runtimeBytes, windowsHide: true },
      );
      stdout = result.stdout;
    } catch (error) {
      // A nonzero exit may carry a definitive refusal. Never retry a mutation here.
      const output = (error as { stdout?: string }).stdout;
      if (!output)
        throw bridgeError(
          'delivery_unknown',
          '操作の完了を確認できません。再送する前に Mac 側を確認してください。',
        );
      stdout = output;
    }
    try {
      const response = JSON.parse(stdout);
      if (response.ok === false)
        throw bridgeError(
          response.error?.code ?? 'orca_error',
          'Orca が操作を拒否しました。Mac 側を確認してください。',
        );
      if (response.ok !== true || !response.result) throw new Error('Invalid response');
      return response.result;
    } catch (error) {
      if (isBridgeError(error)) throw error;
      throw bridgeError(
        'delivery_unknown',
        '操作の結果を読み取れません。再送する前に Mac 側を確認してください。',
      );
    }
  };
}

interface Terminal {
  handle: string;
  title?: string;
  worktreePath?: string;
  branch?: string;
  agentIdentity?: string;
  connected?: boolean;
  writable?: boolean;
  orphaned?: boolean;
  lastOutputAt?: number;
  preview?: string;
}

export interface OrcaGateway {
  sessions: () => Promise<Session[]>;
  output: (id: string) => Promise<SessionOutput>;
  send: (id: string, text: string) => Promise<ActionReceipt>;
  stop: (id: string) => Promise<ActionReceipt>;
}

/** Adapt Orca terminal sessions and distinguish input acceptance from observed execution. */
export function createOrcaGateway(rpc: RuntimeCall, cli: CliCall): OrcaGateway {
  async function runningAgent(id: string) {
    const { agentStatus } = await rpc<{
      agentStatus: { isRunningAgent: boolean; status?: string };
    }>('terminal.agentStatus', { terminal: id });
    if (!agentStatus?.isRunningAgent) {
      throw bridgeError(
        'not_an_agent',
        'このセッションではエージェントが動いていません。Mac でエージェントを開いてください。',
        409,
      );
    }
    return agentStatus;
  }

  async function send(id: string, text: string, interrupt = false): Promise<ActionReceipt> {
    await runningAgent(id);
    const result = await cli([
      'terminal',
      'send',
      '--terminal',
      id,
      '--text',
      text,
      ...(interrupt ? ['--interrupt'] : ['--enter', '--wait-submit', '2']),
    ]);
    const receipt = result.send as
      | {
          accepted?: boolean;
          prompt?: { requestId?: string; observation?: string; stages?: string[] };
        }
      | undefined;
    if (!receipt)
      throw bridgeError('delivery_unknown', '操作結果が不明です。Mac 側を確認してください。');
    const accepted = receipt.accepted === true;
    const observed = receipt.prompt?.stages?.includes('turn_started');
    return {
      accepted,
      message: !accepted
        ? 'Orca が操作を受け付けませんでした。'
        : interrupt
          ? '停止の入力を送りました。停止したか出力を確認してください。'
          : observed
            ? '指示を送信し、実行開始を確認しました。'
            : '入力を受け付けました。実行開始は未確認です。再送する前に出力を確認してください。',
      requestId: receipt.prompt?.requestId,
      observation: receipt.prompt?.observation,
    };
  }

  return {
    async sessions() {
      const result = await rpc<{ terminals: Terminal[]; truncated?: boolean }>('terminal.list', {
        limit: LIMITS.terminalCount,
        includeVisualLayouts: false,
      });
      return result.terminals
        .filter((terminal) => terminal.agentIdentity && !terminal.orphaned)
        .map((terminal) => ({
          id: terminal.handle,
          title: cleanOutput(terminal.title ?? terminal.agentIdentity ?? 'Session'),
          project: basename(terminal.worktreePath ?? '') || 'Workspace',
          branch: (terminal.branch ?? '').replace(/^refs\/heads\//, ''),
          agent: terminal.agentIdentity ?? '',
          connected: terminal.connected === true,
          writable: terminal.writable === true,
          updatedAt: terminal.lastOutputAt ?? null,
          preview: cleanOutput(terminal.preview ?? ''),
        }))
        .sort((a, b) => (b.updatedAt ?? 0) - (a.updatedAt ?? 0));
    },
    async output(id) {
      const [read, status] = await Promise.all([
        rpc<{
          terminal: {
            tail: string[];
            source?: string;
            status?: string;
            truncated?: boolean;
            agentSessionRefusal?: unknown;
          };
        }>('terminal.read', { terminal: id, screen: true, limit: LIMITS.outputCharacters }),
        rpc<{ agentStatus: { isRunningAgent?: boolean; status?: string } }>(
          'terminal.agentStatus',
          { terminal: id },
        ),
      ]);
      if (!Array.isArray(read.terminal?.tail)) {
        throw bridgeError(
          'unsupported_session',
          'この表示形式は未対応です。Orca のターミナル表示のセッションを選んでください。',
          409,
        );
      }
      const raw = status.agentStatus?.status;
      const state =
        read.terminal.status === 'exited'
          ? 'offline'
          : !status.agentStatus?.isRunningAgent
            ? 'idle'
            : raw === 'working'
              ? 'working'
              : raw === 'waiting' || raw === 'permission' || raw === 'input-required'
                ? 'waiting'
                : raw === 'idle'
                  ? 'idle'
                  : 'unknown';
      return {
        sessionId: id,
        state,
        lines: read.terminal.tail.map(cleanOutput),
        source: read.terminal.source === 'screen' ? 'screen' : 'history',
        truncated: read.terminal.truncated === true,
        capturedAt: Date.now(),
      };
    },
    send: (id, text) => send(id, text),
    stop: (id) => send(id, '\u0003', true),
  };
}
