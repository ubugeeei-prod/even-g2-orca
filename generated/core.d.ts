/** JSON-encoded page array; see core/display.mbt for Unicode and bounds policy. */
export function paginate_json(input: string, columns: number, rows: number): string;
/** Heading clipping by display cells, preserving Unicode code points. */
export function clip_text(text: string, columns: number): string;
/** Immutable reader transition; output is JSON { page, following }. */
export function reduce_reader_json(
  page: number,
  following: boolean,
  event: string,
  delta: number,
  count: number,
): string;
/** Pure view transition and effect description, interpreted by the hardware adapter. */
export function navigation_json(
  view: string,
  gesture: string,
  selection: number,
  count: number,
  action: number,
  actionCount: number,
): string;
