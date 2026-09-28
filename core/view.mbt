///|
/// The three text containers on the glasses.
pub(all) struct Frame {
  title : String
  body : String
  footer : String
} derive(Eq, Debug)

///|
pub extend Frame with Eq::{not_equal, equal}

///|
pub extend Frame with Debug::{to_repr}

///|
pub fn Frame::to_json(self : Frame) -> Json {
  {
    "title": Json::string(self.title),
    "body": Json::string(self.body),
    "footer": Json::string(self.footer),
  }
}

///|
fn join(lines : Array[String]) -> String {
  let out = StringBuilder()
  for i, line in lines {
    if i > 0 {
      out.write_char('\n')
    }
    out.write_string(line)
  }
  out.to_string()
}

///|
fn heading(model : Model, text : String) -> String {
  let suffix = match model.connection {
    Offline(_) => " [接続切れ]"
    _ => ""
  }
  clip_text(text, HEADING_COLUMNS - text_width(suffix)) + suffix
}

///|
fn session_lines(model : Model) -> Array[String] {
  let count = model.sessions.length()
  if count == 0 {
    return match model.connection {
      Connecting => ["読み込み中..."]
      Offline(message) => wrap_text(message, BODY_COLUMNS)
      Online =>
        [
          "セッションがありません", "Mac で Orca を開いてください",
        ]
    }
  }
  let index = model.cursor_index()
  let last_first = if count > SESSIONS_PER_PAGE {
    count - SESSIONS_PER_PAGE
  } else {
    0
  }
  let first = clamp(index - 1, 0, last_first)
  let lines : Array[String] = []
  for i in first..<(first + SESSIONS_PER_PAGE) {
    if i >= count {
      break
    }
    let s = model.sessions[i]
    let mark = if i == index { "> " } else { "  " }
    lines.push(
      mark +
      clip_text("\{clip_text(s.project, 12)} / \{s.title}", BODY_COLUMNS - 2),
    )
  }
  lines
}

///|
/// Render the glasses frame. Pure: same model, same frame.
pub fn Model::frame(self : Model) -> Frame {
  match self.screen {
    Setup =>
      {
        title: "接続設定",
        body: "スマホでブリッジに接続してください",
        footer: "",
      }
    Sessions => {
      let count = self.sessions.length()
      let position = if count == 0 {
        ""
      } else {
        " \{self.cursor_index() + 1}/\{count}"
      }
      {
        title: heading(self, "セッション" + position),
        body: join(session_lines(self)),
        footer: if count > 0 {
          "タップで開く"
        } else {
          ""
        },
      }
    }
    Reading => {
      let pages = self.output_pages()
      let page = clamp(self.page, 0, pages.length() - 1)
      let title = match self.selected_session() {
        Some(s) => s.title
        None => "出力"
      }
      let state = match self.shown {
        Some(o) => o.state.label()
        None => "読み込み中"
      }
      let body = match self.shown {
        Some(_) =>
          if pages[page].is_empty() {
            "出力待ち"
          } else {
            join(pages[page])
          }
        None =>
          match self.connection {
            Offline(message) => join(wrap_text(message, BODY_COLUMNS))
            _ => "読み込み中..."
          }
      }
      let fresh = match (self.shown, self.latest) {
        (Some(a), Some(b)) if !self.follow && a.captured_at != b.captured_at =>
          "新着あり"
        _ => ""
      }
      let position = if pages.length() > 1 {
        "\{page + 1}/\{pages.length()}"
      } else {
        ""
      }
      let note = if fresh != "" {
        fresh
      } else if !self.follow {
        "一時停止"
      } else {
        ""
      }
      let footer = if position == "" {
        note
      } else if note == "" {
        position
      } else {
        "\{position}  \{note}"
      }
      { title: heading(self, "\{state}  \{title}"), body, footer, }
    }
    Menu => {
      let items = self.menu_items()
      let last_first = if items.length() > BODY_ROWS {
        items.length() - BODY_ROWS
      } else {
        0
      }
      let first = clamp(self.menu - 1, 0, last_first)
      let lines : Array[String] = []
      for i in first..<items.length() {
        if lines.length() >= BODY_ROWS {
          break
        }
        lines.push(
          (if i == self.menu { "> " } else { "  " }) + items[i].label(),
        )
      }
      {
        title: heading(self, "操作"),
        body: join(lines),
        footer: "\{self.menu + 1}/\{items.length()}  タップで決定",
      }
    }
    ConfirmPrompt => {
      let pages = self.draft_pages()
      let page = clamp(self.draft_page, 0, pages.length() - 1)
      let last = page == pages.length() - 1
      {
        title: heading(
          self,
          "送信内容の確認 \{page + 1}/\{pages.length()}",
        ),
        body: join(pages[page]),
        footer: if last {
          "タップで送信  ダブルで取消"
        } else {
          "タップで次へ  ダブルで取消"
        },
      }
    }
    ConfirmStop =>
      {
        title: heading(self, "停止の確認"),
        body: "実行を停止しますか？",
        footer: "タップで停止  ダブルで取消",
      }
    Recording =>
      {
        title: heading(self, "録音中"),
        body: "話してください",
        footer: "離して終了  ダブルで取消",
      }
    Transcribing =>
      {
        title: heading(self, "認識中"),
        body: "音声を文字にしています",
        footer: "ダブルで取消",
      }
    Sending =>
      {
        title: heading(self, "送信中"),
        body: "Orca に送っています",
        footer: "",
      }
    Notice =>
      {
        title: heading(self, "結果"),
        body: join(paginate(wrap_text(self.notice, BODY_COLUMNS), BODY_ROWS)[0]),
        footer: "タップで戻る",
      }
  }
}
