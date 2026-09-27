export type AgentState = 'working' | 'waiting' | 'idle' | 'offline' | 'unknown';

export interface Session {
  id: string;
  title: string;
  project: string;
  branch: string;
  agent: string;
  connected: boolean;
  writable: boolean;
  updatedAt: number | null;
  preview: string;
}

export interface SessionOutput {
  sessionId: string;
  state: AgentState;
  lines: string[];
  source: 'screen' | 'history';
  truncated: boolean;
  capturedAt: number;
}

export interface BridgeInfo {
  version: string;
  speechAvailable: boolean;
  runtimeReady: boolean;
  sessionCount: number;
}

export interface ActionReceipt {
  accepted: boolean;
  message: string;
  requestId?: string;
  observation?: string;
}

export interface ApiErrorBody {
  error: { code: string; message: string };
}
