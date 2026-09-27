import { BRIDGE_DEFAULTS, LIMITS } from '../shared/config.ts';
import { randomBytes } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { networkInterfaces } from 'node:os';
import QRCode from 'qrcode';
import { createBridgeServer } from './http.ts';
import { createCliCall, createOrcaGateway } from './orca.ts';
import { createRuntimeCall } from './runtime.ts';
import { speechAvailable, transcribe } from './speech.ts';

async function getToken(): Promise<string> {
  if (process.env.BRIDGE_TOKEN) {
    if (process.env.BRIDGE_TOKEN.length < LIMITS.minTokenCharacters)
      throw new Error('BRIDGE_TOKEN must be at least 24 characters.');
    return process.env.BRIDGE_TOKEN;
  }
  await mkdir('.local', { recursive: true, mode: 0o700 });
  try {
    return (await readFile('.local/bridge-token', 'utf8')).trim();
  } catch {
    const token = randomBytes(32).toString('base64url');
    await writeFile('.local/bridge-token', token, { mode: 0o600, flag: 'wx' });
    return token;
  }
}

const token = await getToken();
const port = Number(process.env.BRIDGE_PORT ?? BRIDGE_DEFAULTS.port);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid BRIDGE_PORT');
const host = process.env.BRIDGE_HOST ?? BRIDGE_DEFAULTS.host;
const lan =
  Object.values(networkInterfaces())
    .flat()
    .find((address) => address && address.family === 'IPv4' && !address.internal)?.address ??
  'localhost';
const publicUrl = new URL(process.env.BRIDGE_PUBLIC_URL ?? `http://${lan}:${port}`);
if (
  !['http:', 'https:'].includes(publicUrl.protocol) ||
  publicUrl.username ||
  publicUrl.password ||
  publicUrl.pathname !== '/' ||
  publicUrl.search ||
  publicUrl.hash
)
  throw new Error('BRIDGE_PUBLIC_URL must be an HTTP(S) origin.');
const server = createBridgeServer({
  token,
  orca: createOrcaGateway(createRuntimeCall(), await createCliCall()),
  publicOrigin: publicUrl.origin,
  allowedOrigins: process.env.BRIDGE_ALLOWED_ORIGINS?.split(',')
    .map((value) => value.trim())
    .filter(Boolean),
  speechAvailable: speechAvailable(),
  transcribe,
});
server.listen(port, host, () => {
  console.log(`Orca for G2 bridge: ${publicUrl.origin}`);
  console.log('Even App の開発用 QR またはスマートフォンのブラウザで開いてください。');
  console.log('この QR と URL はあなたの Orca を操作できるため、共有しないでください。');
  const pairing = `${publicUrl.origin}/#token=${encodeURIComponent(token)}`;
  console.log(pairing);
  void QRCode.toString(pairing, { type: 'terminal', small: true }).then(console.log);
});
server.on('error', (error) => {
  console.error(error.message);
  process.exitCode = 1;
});
for (const signal of ['SIGINT', 'SIGTERM'] as const)
  process.on(signal, () => server.close(() => process.exit(0)));
