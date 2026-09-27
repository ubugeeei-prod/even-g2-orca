/** Hardware layout and conservative text budgets for the Even G2 display. */
export const DISPLAY = {
  width: 576,
  height: 288,
  inset: 16,
  contentWidth: 544,
  heading: { y: 4, height: 36 },
  body: { y: 44, height: 192 },
  footer: { y: 246, height: 38 },
  columns: 58,
  rows: 6,
  sessionsPerPage: 3,
} as const;

/** Timing policies are shared by adapters and tests; milliseconds unless stated. */
export const TIMING = {
  poll: 2_000,
  reconnect: 8_000,
  sessionList: 10_000,
  runtimeTimeout: 15_000,
  httpTimeout: 20_000,
  cliTimeout: 25_000,
  actionTimeout: 35_000,
  speechTimeout: 120_000,
  recording: 60_000,
  operationRetention: 24 * 60 * 60 * 1_000,
} as const;

/** Memory and wire limits constrain untrusted network and runtime responses. */
export const LIMITS = {
  runtimeBytes: 4 * 1024 * 1024,
  jsonBodyBytes: 32 * 1024,
  promptCharacters: 16_000,
  terminalCount: 200,
  outputCharacters: 30_000,
  operations: 10_000,
  minTokenCharacters: 24,
} as const;

/** The public SDK microphone stream is 16 kHz signed little-endian PCM16 mono. */
export const AUDIO = {
  sampleRate: 16_000,
  bitsPerSample: 16,
  channels: 1,
  bytesPerSecond: 32_000,
  maxBytes: 1_920_000,
  wavHeaderBytes: 44,
} as const;

/** Default listener. A device must use its Mac's reachable address, not localhost. */
export const BRIDGE_DEFAULTS = { host: '0.0.0.0', port: 3210, devPort: 5173 } as const;
