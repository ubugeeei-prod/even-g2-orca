import { createBridgeServer } from '../../server/http.ts';
import type { OrcaGateway } from '../../server/orca.ts';

/** Deterministic HTTP fixture; browser tests never invoke or mutate a real Orca session. */
const orca: OrcaGateway = {
  sessions: async () => [
    {
      id: 'demo',
      title: 'Even G2 アプリの実装',
      project: 'even-g2-orca',
      branch: 'feat/even-g2-orca',
      agent: 'claude',
      connected: true,
      writable: true,
      updatedAt: Date.now(),
      preview: '画面の検証が完了しました。',
    },
  ],
  output: async (sessionId) => ({
    sessionId,
    state: 'working',
    source: 'screen',
    truncated: false,
    capturedAt: Date.now(),
    lines: [
      'セッション一覧とタッチ入力を実装しました。',
      '日本語の表示を確認しています。',
      '接続設定を確認しました。',
      '最新の出力は自動で更新されます。',
      'スワイプすると閲覧中のページを固定します。',
      '操作は確認画面を経てから実行します。',
      'MoonBit のページ分割テストが通りました。',
      'Cloudflare の設定を検証しました。',
      '現在、アプリの表示を確認しています。',
      '残りの作業：実機との接続確認。',
    ],
  }),
  send: async () => ({ accepted: true, message: '指示を送信し、実行開始を確認しました。' }),
  stop: async () => ({
    accepted: true,
    message: '停止の入力を送りました。停止したか出力を確認してください。',
  }),
};
const server = createBridgeServer({ token: 'test-pairing-token-for-browser', orca });
server.listen(4321, '127.0.0.1');
for (const signal of ['SIGINT', 'SIGTERM'] as const)
  process.on(signal, () => server.close(() => process.exit(0)));
