///|
/// Even G2 canvas in pixels. Containers are laid out inside it by the app shell.
pub const DISPLAY_WIDTH : Int = 576

///|
pub const DISPLAY_HEIGHT : Int = 288

///|
/// Conservative text budget of the body container, in display cells.
pub const BODY_COLUMNS : Int = 56

///|
pub const BODY_ROWS : Int = 6

///|
pub const HEADING_COLUMNS : Int = 52

///|
pub const SESSIONS_PER_PAGE : Int = 3

///|
/// Polling cadence in milliseconds.
pub const POLL_MS : Int = 2000

///|
pub const SESSION_LIST_MS : Int = 10000

///|
pub const RECONNECT_MS : Int = 8000

///|
/// Wire limits for untrusted input.
pub const MAX_PROMPT_CHARS : Int = 16000

///|
pub const MAX_JSON_BODY_BYTES : Int = 64 * 1024

///|
pub const MAX_AUDIO_BYTES : Int = 2 * 1024 * 1024

///|
pub const MAX_OUTPUT_LINES : Int = 400

///|
pub const MAX_TERMINALS : Int = 200

///|
/// Operation ids are remembered for a day to suppress duplicated deliveries.
pub const OPERATION_RETENTION_MS : Double = 86400000.0

///|
pub const MAX_OPERATIONS : Int = 10000

///|
pub const MIN_TOKEN_CHARS : Int = 24
