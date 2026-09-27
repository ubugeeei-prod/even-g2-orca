import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import app from '../app.json' with { type: 'json' };
import pkg from '../package.json' with { type: 'json' };

/** Build an Even Hub package with its actual network permission origin, never a token. */
const input =
  process.argv.slice(2).find((argument) => argument !== '--') ?? process.env.BRIDGE_PUBLIC_URL;
if (!input) throw new Error('Usage: vp run pack -- https://your-worker.workers.dev');
const origin = new URL(input);
if (
  !['https:', 'http:'].includes(origin.protocol) ||
  origin.pathname !== '/' ||
  origin.search ||
  origin.hash ||
  origin.username ||
  origin.password
)
  throw new Error('Specify an HTTP(S) origin without credentials, path, query or fragment.');
execFileSync('node_modules/.bin/vp', ['build'], {
  stdio: 'inherit',
  env: { ...process.env, VITE_BRIDGE_ORIGIN: origin.origin },
});
writeFileSync(
  'app.local.json',
  JSON.stringify(
    {
      ...app,
      version: pkg.version,
      min_sdk_version: pkg.dependencies['@evenrealities/even_hub_sdk'],
      permissions: app.permissions.map((permission) =>
        permission.name === 'network' ? { ...permission, whitelist: [origin.origin] } : permission,
      ),
    },
    null,
    2,
  ) + '\n',
);
execFileSync(
  'node_modules/.bin/evenhub',
  [
    'pack',
    'app.local.json',
    'dist',
    '--sdk-ver',
    pkg.dependencies['@evenrealities/even_hub_sdk'],
    '-o',
    'even-g2-orca.ehpk',
  ],
  { stdio: 'inherit' },
);
