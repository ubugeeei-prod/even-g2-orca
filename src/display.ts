import type { Session, SessionOutput } from '../shared/protocol.ts';
import { DISPLAY } from '../shared/config.ts';
import { clip_text, paginate_json } from '../generated/core.js';
import { cleanOutput } from '../shared/text.ts';
export { cleanOutput } from '../shared/text.ts';

export interface DisplayFrame {
  title: string;
  body: string;
  footer: string;
}

/** The MoonBit core owns wrapping and paging, shared by browser and glasses. */
export function paginate(lines: string[], rows: number = DISPLAY.rows): string[] {
  const pages: string[] = JSON.parse(
    paginate_json(JSON.stringify(lines.map(cleanOutput)), DISPLAY.columns, rows),
  );
  return pages.length && pages.some(Boolean) ? pages : ['出力を待っています'];
}

/** Clip by display cells rather than UTF-16 length. */
export function clip(value: string, max: number): string {
  return clip_text(cleanOutput(value).replace(/\n/g, ' '), max);
}

export const stateLabel = {
  working: '実行中',
  waiting: '入力待ち',
  idle: '待機中',
  offline: '切断',
  unknown: '状態不明',
} as const;

/** Format a stable, bounded frame without altering the underlying output snapshot. */
export function outputFrame(
  session: Session,
  output: SessionOutput,
  page: number,
  following: boolean,
): DisplayFrame {
  const pages = paginate(output.lines);
  const index = Math.max(0, Math.min(page, pages.length - 1));
  return {
    title: clip(`${stateLabel[output.state]} | ${session.project} / ${session.title}`, 57),
    body: pages[index] ?? '',
    footer: `${index + 1}/${pages.length}  ${following ? 'LIVE' : 'PAUSED'}  Swipe:頁 Tap:操作 Double:一覧`,
  };
}

/** Three two-line entries fit the configured six-row content region. */
export function sessionsFrame(sessions: Session[], selected: number): DisplayFrame {
  const start = Math.floor(selected / DISPLAY.sessionsPerPage) * DISPLAY.sessionsPerPage;
  return {
    title: 'ORCA / セッション',
    body: sessions.length
      ? sessions
          .slice(start, start + DISPLAY.sessionsPerPage)
          .map(
            (session, index) =>
              `${start + index === selected ? '>' : ' '} ${clip(session.title, 52)}\n  ${clip(session.project, 50)}`,
          )
          .join('\n')
      : 'エージェントセッションがありません\nMac の Orca でエージェントを開いてください',
    footer: 'Swipe:選択  Tap:開く  Double:更新',
  };
}
