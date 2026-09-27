/** Stable public error contract; never return credentials or raw child-process output. */
export const bridgeError = (code: string, message: string, status = 502) =>
  Object.assign(new Error(message), { code, status });

export type BridgeError = ReturnType<typeof bridgeError>;

/** Recognize our error values without relying on a subclass across module boundaries. */
export function isBridgeError(error: unknown): error is BridgeError {
  return error instanceof Error && 'code' in error && 'status' in error;
}

/** Sanitize unknown failures at the HTTP boundary. */
export function publicError(error: unknown): BridgeError {
  return isBridgeError(error)
    ? error
    : bridgeError(
        'bridge_error',
        'ブリッジでエラーが発生しました。Mac 側の接続を確認してください。',
      );
}
