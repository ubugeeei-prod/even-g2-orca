///|
test "clean_terminal_text strips CSI, OSC and controls" {
  let raw = "\u{1b}[1;32mok\u{1b}[0m\u{1b}]0;title\u{7} done\tx\u{0}\r"
  @debug.debug_inspect(
    clean_terminal_text(raw),
    content=(
      #|"ok done    x"
    ),
  )
  @debug.debug_inspect(
    clean_terminal_text("a\u{1b}]8;;http://x\u{1b}\\link\u{1b}]8;;\u{1b}\\b"),
    content=(
      #|"alinkb"
    ),
  )
}

///|
test "cell widths count wide glyphs as two cells" {
  @debug.debug_inspect(text_width("abc"), content="3")
  @debug.debug_inspect(text_width("日本語"), content="6")
  @debug.debug_inspect(text_width("e\u{301}"), content="1")
}

///|
test "wrap_text respects cells and keeps blank lines" {
  json_inspect(wrap_text("あいうえお", 4), content=[
    "あい", "うえ", "お",
  ])
  json_inspect(wrap_text("ab\n\ncd", 10), content=["ab", "", "cd"])
  json_inspect(wrap_text("abcde", 1), content=["ab", "cd", "e"])
}

///|
test "paginate always yields a page" {
  json_inspect(paginate([], 3), content=[[]])
  json_inspect(paginate(["a", "b", "c", "d"], 3), content=[
    ["a", "b", "c"],
    ["d"],
  ])
}

///|
test "clip_text marks truncation within the budget" {
  @debug.debug_inspect(
    clip_text("short", 10),
    content=(
      #|"short"
    ),
  )
  @debug.debug_inspect(
    clip_text("日本語のタイトル", 8),
    content=(
      #|"日本語.."
    ),
  )
  @debug.debug_inspect(
    text_width(clip_text("日本語のタイトル", 8)) <= 8,
    content="true",
  )
}

///|
test "helpers" {
  @debug.debug_inspect(
    trim_end_spaces("ab   "),
    content=(
      #|"ab"
    ),
  )
  @debug.debug_inspect(
    basename("/Users/me/src/project/"),
    content=(
      #|"project"
    ),
  )
  @debug.debug_inspect(
    basename(""),
    content=(
      #|""
    ),
  )
  json_inspect(drop_trailing_blank(["a", "", "b", "", ""]), content=[
    "a", "", "b",
  ])
}

///|
test "display_line hides decorative rules only" {
  @debug.debug_inspect(display_line("─".repeat(72)), content="\"\"")
  @debug.debug_inspect(
    display_line("── title ──────"),
    content="\"── title ──────\"",
  )
  @debug.debug_inspect(display_line("--"), content="\"--\"")
}

///|
test "paginate_from_end keeps the newest page full" {
  json_inspect(paginate_from_end(["a", "b", "c", "d"], 3), content=[
    ["a"],
    ["b", "c", "d"],
  ])
  json_inspect(paginate_from_end([], 3), content=[[]])
}
