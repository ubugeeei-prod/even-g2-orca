///|
/// Immutable reader state. Page movements pause the visible snapshot, while
/// subsequent arrivals only move the page when follow mode is enabled.
pub(all) struct Reader {
  page : Int
  following : Bool
} derive(Eq, Debug)

///|
/// Explicit events keep navigation independent of network and hardware effects.
pub(all) enum ReaderEvent {
  Move(Int)
  ToggleFollow
  Arrived
  Open
} derive(Eq, Debug)

///|
/// Clamp all pages, including empty outputs and disappearing sessions.
pub fn reduce_reader(
  state : Reader,
  event : ReaderEvent,
  page_count : Int,
) -> Reader {
  let last = if page_count > 0 { page_count - 1 } else { 0 }
  fn clamp(page) {
    if page < 0 {
      0
    } else if page > last {
      last
    } else {
      page
    }
  }
  match event {
    Move(delta) => { page: clamp(state.page + delta), following: false }
    ToggleFollow =>
      {
        page: if state.following {
          clamp(state.page)
        } else {
          last
        },
        following: !state.following,
      }
    Arrived =>
      {
        page: if state.following {
          last
        } else {
          clamp(state.page)
        },
        following: state.following,
      }
    Open => { page: last, following: true }
  }
}

///|
/// Stable JS adapter. Events use names instead of compiler-specific enum values.
pub fn reduce_reader_json(
  page : Int,
  following : Bool,
  event : String,
  delta : Int,
  count : Int,
) -> String {
  let action = match event {
    "move" => Move(delta)
    "toggle" => ToggleFollow
    "open" => Open
    _ => Arrived
  }
  let state = reduce_reader({ page, following }, action, count)
  { "page": state.page.to_json(), "following": state.following.to_json() }
  .to_json()
  .stringify()
}
