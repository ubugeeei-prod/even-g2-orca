import { defineConfig } from 'vite-plus';
import { execFileSync } from 'node:child_process';
import { BRIDGE_DEFAULTS } from './shared/config.ts';

export default defineConfig({
  base: './',
  server: {
    proxy: { '/api': `http://127.0.0.1:${process.env.BRIDGE_PORT ?? BRIDGE_DEFAULTS.port}` },
  },
  plugins: [
    {
      name: 'moonbit-core',
      buildStart() {
        execFileSync(process.execPath, ['scripts/build-core.ts'], { stdio: 'inherit' });
      },
    },
  ],
  lint: {
    options: { typeAware: true, typeCheck: true },
    ignorePatterns: [
      'dist/**',
      '_build/**',
      'generated/*.js',
      'test-results/**',
      'playwright-report/**',
      '.local/**',
      '.wrangler/**',
    ],
    overrides: [
      { files: ['shared/text.ts', 'server/http.ts'], rules: { 'no-control-regex': 'off' } },
    ],
  },
  fmt: {
    singleQuote: true,
    printWidth: 100,
    ignorePatterns: ['_build/**', 'generated/*.js', '.local/**', '.wrangler/**'],
  },
  test: { include: ['tests/**/*.test.ts'] },
  run: {
    tasks: {
      'build:core': { command: 'node scripts/build-core.ts', cache: false },
      'test:core': { command: 'moon test --target js --deny-warn', cache: false },
    },
  },
});
