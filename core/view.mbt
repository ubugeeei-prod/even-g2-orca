///|
/// The three text containers on the glasses.
pub(all) struct Frame {
  title : String
  body : String
  footer : String
} derive(Eq, Debug)

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
          "エージェントのセッションがありません。", "Mac の Orca でエージェントを起動してください。",
        ]
    }
  }
  let index = model.cursor_index()
  let first = index / SESSIONS_PER_PAGE * SESSIONS_PER_PAGE
  let lines : Array[String] = []
  for i in first..<(first + SESSIONS_PER_PAGE) {
    if i >= count {
      break
    }
    let s = model.sessions[i]
    let mark = if i == index { "> " } else { "  " }
    lines.push(mark + clip_text(s.title, BODY_COLUMNS - 2))
    let detail = if s.branch.length() > 0 {
      "\{s.project} / \{s.branch}"
    } else {
      s.project
    }
    lines.push("  " + clip_text(detail, BODY_COLUMNS - 2))
  }
  lines
}

///|
/// Render the glasses frame. Pure: same model, same frame.
pub fn Model::frame(self : Model) -> Frame {
  match self.screen {
    Setup =>
      {
        title: "Orca for G2",
        body: join(
          wrap_text(
            "スマートフォンでブリッジの接続先とペアリング用トークンを設定してください。",
            BODY_COLUMNS,
          ),
        ),
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
        footer: "上下 選択  タップ 開く  ダブル 更新",
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
        Some(_) => join(pages[page])
        None =>
          match self.connection {
            Offline(message) => join(wrap_text(message, BODY_COLUMNS))
            _ => "読み込み中..."
          }
      }
      let mode = if self.follow { "追従" } else { "一時停止" }
      let fresh = match (self.shown, self.latest) {
        (Some(a), Some(b)) if !self.follow && a.captured_at != b.captured_at =>
          " 新着あり"
        _ => ""
      }
      {
        title: heading(self, "\{state} | \{title}"),
        body,
        footer: "\{page + 1}/\{pages.length()} \{mode}\{fresh}  タップ 操作",
      }
    }
    Menu => {
      let items = self.menu_items()
      let lines = items.mapi(fn(i, item) {
        (if i == self.menu { "> " } else { "  " }) + item.label()
      })
      {
        title: heading(self, "操作"),
        body: join(lines),
        footer: "タップ 決定  ダブル 戻る",
      }
    }
    ConfirmPrompt => {
      let pages = self.draft_pages()
      let page = clamp(self.draft_page, 0, pages.length() - 1)
      let last = page == pages.length() - 1
      let lines = pages[page].copy()
      if last {
        lines.push("-- タップで送信 --")
      }
      {
        title: heading(
          self,
          "送信内容の確認 \{page + 1}/\{pages.length()}",
        ),
        body: join(lines),
        footer: if last {
          "タップ 送信  ダブル 取消"
        } else {
          "タップ 次へ  ダブル 取消"
        },
      }
    }
    ConfirmStop =>
      {
        title: heading(self, "停止の確認"),
        body: join(
          wrap_text(
            "Ctrl-C を送ってエージェントの実行を止めますか？",
            BODY_COLUMNS,
          ),
        ),
        footer: "タップ 停止  ダブル 取消",
      }
    Recording =>
      {
        title: heading(self, "録音中"),
        body: "話し終えたら離すかタップしてください。",
        footer: "ダブル 取消",
      }
    Transcribing =>
      {
        title: heading(self, "認識中"),
        body: "Mac で音声を認識しています...",
        footer: "ダブル 取消",
      }
    Sending =>
      {
        title: heading(self, "送信中"),
        body: "Orca に送っています...",
        footer: "",
      }
    Notice =>
      {
        title: heading(self, "結果"),
        body: join(paginate(wrap_text(self.notice, BODY_COLUMNS), BODY_ROWS)[0]),
        footer: "タップ 出力へ",
      }
  }
}
