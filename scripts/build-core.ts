import { execFileSync } from 'node:child_process';
import { copyFileSync, mkdirSync } from 'node:fs';
import { existsSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

/** Compile the deterministic MoonBit core to the ESM consumed by both adapters. */
const userMoon = join(homedir(), '.moon/bin/moon');
const moon = process.env.MOON_BIN ?? (existsSync(userMoon) ? userMoon : 'moon');
execFileSync(moon, ['build', '--target', 'js', '--release', '--deny-warn'], { stdio: 'inherit' });
mkdirSync('generated', { recursive: true });
copyFileSync('_build/js/release/build/core/core.js', 'generated/core.js');
