///|
/// Normalized G2 / R1 input.
pub(all) enum Gesture {
  Up
  Down
  Tap
  DoubleTap
  Hold
  Release
  /// The app left the foreground or the system exited it.
  Exit
} derive(Eq, Debug)

///|
pub(all) enum Screen {
  Setup
  Sessions
  Reading
  Menu
  ConfirmPrompt
  ConfirmStop
  Recording
  Transcribing
  Sending
  Notice
} derive(Eq, Debug)

///|
pub(all) enum MenuItem {
  Dictate
  Continue
  Latest
  Stop
  Back
} derive(Eq, Debug)

///|
pub fn MenuItem::label(self : MenuItem) -> String {
  match self {
    Dictate => "音声で指示する"
    Continue => "「続けて」と送る"
    Latest => "最新の出力へ"
    Stop => "実行を停止する"
    Back => "セッション一覧へ"
  }
}

///|
pub(all) enum Connection {
  Connecting
  Online
  Offline(String)
} derive(Eq, Debug)

///|
/// Everything the glasses show is derived from this value.
pub(all) struct Model {
  mut screen : Screen
  mut sessions : Array[Session]
  mut cursor : String?
  mut selected : String?
  /// The snapshot being read. Frozen while not following.
  mut shown : Output?
  /// The newest snapshot received.
  mut latest : Output?
  mut follow : Bool
  mut page : Int
  mut menu : Int
  mut draft : String
  mut draft_page : Int
  mut notice : String
  mut connection : Connection
  /// Bumped on every navigation that invalidates in-flight responses.
  mut generation : Int
  mut speech : Bool
  mut configured : Bool
} derive(Debug)

///|
pub fn Model::new() -> Model {
  {
    screen: Setup,
    sessions: [],
    cursor: None,
    selected: None,
    shown: None,
    latest: None,
    follow: true,
    page: 0,
    menu: 0,
    draft: "",
    draft_page: 0,
    notice: "",
    connection: Connecting,
    generation: 0,
    speech: false,
    configured: false,
  }
}

///|
pub(all) enum Msg {
  /// Connection settings are present (or were just saved).
  Configured(Bool)
  Info(BridgeInfo)
  Gesture(Gesture)
  SessionsLoaded(Int, Array[Session])
  SessionsFailed(Int, ApiError)
  OutputLoaded(Int, Output)
  OutputFailed(Int, ApiError)
  Tick(Int)
  ActionDone(Receipt)
  ActionFailed(ApiError)
  Transcribed(Int, String)
  VoiceFailed(Int, String)
  /// A prompt typed on the phone, to be confirmed like a dictated one.
  Draft(String)
} derive(Debug)

///|
pub(all) enum Effect {
  LoadInfo
  LoadSessions(Int)
  LoadOutput(Int, String)
  Schedule(Int, Int)
  SendPrompt(String, String)
  SendStop(String)
  StartRecording(Int)
  FinishRecording(Int)
  CancelRecording
} derive(Eq, Debug)

///|
pub fn Model::menu_items(self : Model) -> Array[MenuItem] {
  let items : Array[MenuItem] = []
  if self.speech {
    items.push(Dictate)
  }
  items.push(Continue)
  if !self.follow {
    items.push(Latest)
  }
  items.push(Stop)
  items.push(Back)
  items
}

///|
fn Model::cursor_index(self : Model) -> Int {
  match self.cursor {
    Some(id) =>
      match self.sessions.search_by(fn(s) { s.id == id }) {
        Some(i) => i
        None => 0
      }
    None => 0
  }
}

///|
pub fn Model::selected_session(self : Model) -> Session? {
  match self.selected {
    Some(id) =>
      self.sessions
      .search_by(fn(s) { s.id == id })
      .map(fn(i) { self.sessions[i] })
    None => None
  }
}

///|
/// Pages of the snapshot being read.
pub fn Model::output_pages(self : Model) -> Array[Array[String]] {
  match self.shown {
    Some(output) =>
      paginate_from_end(
        wrap_lines(output.lines.map(display_line), BODY_COLUMNS),
        BODY_ROWS,
      )
    None => paginate([], BODY_ROWS)
  }
}

///|
pub fn Model::draft_pages(self : Model) -> Array[Array[String]] {
  paginate(wrap_text(self.draft, BODY_COLUMNS), BODY_ROWS - 1)
}

///|
fn Model::next_generation(self : Model) -> Int {
  self.generation += 1
  self.generation
}

///|
fn Model::open_sessions(self : Model) -> Array[Effect] {
  self.screen = Sessions
  self.selected = None
  self.shown = None
  self.latest = None
  [LoadSessions(self.next_generation())]
}

///|
fn Model::open_reading(self : Model, id : String) -> Array[Effect] {
  let changed = self.selected != Some(id)
  self.screen = Reading
  self.selected = Some(id)
  if changed {
    self.shown = None
    self.latest = None
    self.follow = true
    self.page = 0
  }
  [LoadOutput(self.next_generation(), id)]
}

///|
/// Invalidate in-flight work (e.g. a pending transcript) and poll afresh.
fn Model::restart_reading(self : Model) -> Array[Effect] {
  match self.selected {
    Some(id) => {
      self.screen = Reading
      [LoadOutput(self.next_generation(), id)]
    }
    None => self.open_sessions()
  }
}

///|
/// Return to the output screen without restarting its polling loop.
fn Model::back_to_reading(self : Model) -> Array[Effect] {
  self.screen = Reading
  []
}

///|
fn Model::show_latest(self : Model) -> Unit {
  self.shown = self.latest
  self.follow = true
  self.page = self.output_pages().length() - 1
}

///|
fn Model::start_draft(self : Model, text : String) -> Unit {
  self.draft = text
  self.draft_page = 0
  self.screen = ConfirmPrompt
}

///|
fn clamp(value : Int, low : Int, high : Int) -> Int {
  if value < low {
    low
  } else if value > high {
    high
  } else {
    value
  }
}

///|
/// The whole reader: a pure transition from a message to effects.
pub fn Model::update(self : Model, msg : Msg) -> Array[Effect] {
  match msg {
    Configured(true) => {
      self.configured = true
      self.connection = Connecting
      [LoadInfo, ..self.open_sessions()]
    }
    Configured(false) => {
      self.configured = false
      self.screen = Setup
      self.generation += 1
      []
    }
    Info(info) => {
      self.speech = info.speech
      []
    }
    SessionsLoaded(generation, sessions) => {
      if generation != self.generation {
        return []
      }
      self.connection = Online
      self.sessions = sessions
      if self.cursor is Some(id) && !sessions.iter().any(fn(s) { s.id == id }) {
        self.cursor = None
      }
      if self.cursor is None && sessions.length() > 0 {
        self.cursor = Some(sessions[0].id)
      }
      if self.screen == Sessions {
        [Schedule(generation, SESSION_LIST_MS)]
      } else {
        []
      }
    }
    SessionsFailed(generation, error) => {
      if generation != self.generation {
        return []
      }
      self.connection = Offline(error.message)
      if error.status == 401 {
        self.screen = Setup
        self.configured = false
        return []
      }
      [Schedule(generation, RECONNECT_MS)]
    }
    OutputLoaded(generation, output) => {
      if generation != self.generation ||
        self.selected != Some(output.session_id) {
        return []
      }
      self.connection = Online
      self.latest = Some(output)
      if self.follow || self.shown is None {
        self.show_latest()
      }
      [Schedule(generation, POLL_MS)]
    }
    OutputFailed(generation, error) => {
      if generation != self.generation {
        return []
      }
      self.connection = Offline(error.message)
      if error.status == 401 {
        self.screen = Setup
        self.configured = false
        return []
      }
      [Schedule(generation, RECONNECT_MS)]
    }
    Tick(generation) => {
      if generation != self.generation || !self.configured {
        return []
      }
      match (self.screen, self.selected) {
        (Sessions, _) => [LoadSessions(generation)]
        (Setup, _) => []
        (_, Some(id)) => [LoadOutput(generation, id)]
        (_, None) => []
      }
    }
    ActionDone(receipt) => {
      if self.screen != Sending {
        return []
      }
      self.notice = receipt.message
      self.screen = Notice
      []
    }
    ActionFailed(error) => {
      if self.screen != Sending {
        return []
      }
      self.notice = error.message
      self.screen = Notice
      []
    }
    Transcribed(generation, text) => {
      if generation != self.generation || self.screen != Transcribing {
        return []
      }
      self.start_draft(text)
      []
    }
    VoiceFailed(generation, message) => {
      if generation != self.generation ||
        !(self.screen is (Recording | Transcribing)) {
        return []
      }
      self.notice = message
      self.screen = Notice
      []
    }
    Draft(text) => {
      if self.selected is None ||
        self.screen is (Setup | Sessions | Sending | Recording | Transcribing) {
        return []
      }
      self.start_draft(text)
      []
    }
    Gesture(gesture) => self.gesture(gesture)
  }
}

///|
fn Model::gesture(self : Model, gesture : Gesture) -> Array[Effect] {
  if gesture == Exit {
    return if self.screen is (Recording | Transcribing) {
      [CancelRecording, ..self.restart_reading()]
    } else {
      []
    }
  }
  match self.screen {
    Setup => []
    Sessions => {
      let count = self.sessions.length()
      match gesture {
        Up | Down if count > 0 => {
          let delta = if gesture == Up { -1 } else { 1 }
          let index = clamp(self.cursor_index() + delta, 0, count - 1)
          self.cursor = Some(self.sessions[index].id)
          []
        }
        Tap if count > 0 =>
          self.open_reading(self.sessions[self.cursor_index()].id)
        DoubleTap => self.open_sessions()
        _ => []
      }
    }
    Reading => {
      let last = self.output_pages().length() - 1
      match gesture {
        Up => {
          self.follow = false
          self.page = clamp(self.page - 1, 0, last)
          []
        }
        Down =>
          if self.page >= last {
            self.show_latest()
            []
          } else {
            self.page += 1
            []
          }
        Tap => {
          self.menu = 0
          self.screen = Menu
          []
        }
        DoubleTap => self.open_sessions()
        Hold =>
          if self.speech {
            self.screen = Recording
            [StartRecording(self.generation)]
          } else {
            []
          }
        _ => []
      }
    }
    Menu => {
      let items = self.menu_items()
      match gesture {
        Up => {
          self.menu = clamp(self.menu - 1, 0, items.length() - 1)
          []
        }
        Down => {
          self.menu = clamp(self.menu + 1, 0, items.length() - 1)
          []
        }
        DoubleTap => self.back_to_reading()
        Tap =>
          match items[clamp(self.menu, 0, items.length() - 1)] {
            Dictate => {
              self.screen = Recording
              [StartRecording(self.generation)]
            }
            Continue => {
              self.start_draft("続けて")
              []
            }
            Latest => {
              self.show_latest()
              self.back_to_reading()
            }
            Stop => {
              self.screen = ConfirmStop
              []
            }
            Back => self.open_sessions()
          }
        _ => []
      }
    }
    ConfirmPrompt => {
      let last = self.draft_pages().length() - 1
      match gesture {
        Up => {
          self.draft_page = clamp(self.draft_page - 1, 0, last)
          []
        }
        Down => {
          self.draft_page = clamp(self.draft_page + 1, 0, last)
          []
        }
        Tap =>
          if self.draft_page < last {
            self.draft_page += 1
            []
          } else {
            match self.selected {
              Some(id) => {
                self.screen = Sending
                [SendPrompt(id, self.draft)]
              }
              None => self.open_sessions()
            }
          }
        DoubleTap => {
          self.draft = ""
          self.back_to_reading()
        }
        _ => []
      }
    }
    ConfirmStop =>
      match gesture {
        Tap =>
          match self.selected {
            Some(id) => {
              self.screen = Sending
              [SendStop(id)]
            }
            None => self.open_sessions()
          }
        DoubleTap => self.back_to_reading()
        _ => []
      }
    Recording =>
      match gesture {
        Tap | Release => {
          self.screen = Transcribing
          [FinishRecording(self.generation)]
        }
        DoubleTap => [CancelRecording, ..self.restart_reading()]
        _ => []
      }
    Transcribing =>
      match gesture {
        DoubleTap => [CancelRecording, ..self.restart_reading()]
        _ => []
      }
    Sending => []
    Notice =>
      match gesture {
        Tap | DoubleTap =>
          match self.selected {
            Some(id) => {
              self.show_latest()
              self.open_reading(id)
            }
            None => self.open_sessions()
          }
        _ => []
      }
  }
}
