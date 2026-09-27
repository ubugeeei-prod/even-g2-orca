///|
/// Pure navigation command. Effects are descriptive strings, interpreted only
/// by the adapter; entering a confirmation view never sends terminal input.
pub fn navigation_json(
  view : String,
  gesture : String,
  selection : Int,
  count : Int,
  action : Int,
  action_count : Int,
) -> String {
  let mut next_view = view
  let mut next_selection = selection
  let mut next_action = action
  let mut effect = "none"
  fn clamp(index, length) {
    if index < 0 || length <= 0 {
      0
    } else if index >= length {
      length - 1
    } else {
      index
    }
  }
  match gesture {
    "up" | "down" => {
      let delta = if gesture == "up" { -1 } else { 1 }
      match view {
        "sessions" => next_selection = clamp(selection + delta, count)
        "actions" => next_action = clamp(action + delta, action_count)
        "output" => effect = if delta < 0 { "page-up" } else { "page-down" }
        "draft" => effect = if delta < 0 { "draft-up" } else { "draft-down" }
        _ => ()
      }
    }
    "back" | "cancel" => {
      if view == "recording" {
        effect = "cancel-recording"
      }
      next_view = if view == "output" {
        "sessions"
      } else if view == "sessions" {
        "sessions"
      } else {
        "output"
      }
      if view == "sessions" {
        effect = "refresh"
      }
    }
    "hold" => if view == "output" { effect = "record" }
    "release" => if view == "recording" { effect = "finish-recording" }
    "tap" =>
      match view {
        "sessions" => effect = if count > 0 { "open" } else { "refresh" }
        "output" => {
          next_view = "actions"
          next_action = 0
        }
        "actions" => effect = "action"
        "draft" => effect = "send"
        "stop" => effect = "stop"
        "recording" => effect = "finish-recording"
        _ => ()
      }
    _ => ()
  }
  {
    "view": next_view.to_json(),
    "selection": next_selection.to_json(),
    "actionSelection": next_action.to_json(),
    "effect": effect.to_json(),
  }
  .to_json()
  .stringify()
}
