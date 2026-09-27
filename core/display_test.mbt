///|
test "mixed Japanese and emoji preserve every code point" {
  let text = "abc日本語🙂def"
  let rows = @core.wrap_text(text, 6)
  assert_eq(rows.join(""), text)
  assert_eq(rows, ["abc日", "本語🙂", "def"])
}

///|
test "blank lines and combining marks stay readable" {
  assert_eq(@core.wrap_text("ab\n\ne\u{0301}f", 2), ["ab", "", "e\u{0301}f"])
}

///|
test "bounds and malformed FFI input do not trap" {
  assert_eq(@core.paginate_json("not json", 0, 0), "[\"\"]")
  assert_eq(@core.paginate_json("[\"abcdef\"]", 3, 1), "[\"abc\",\"def\"]")
}

///|
test "heading clipping includes the marker budget" {
  assert_eq(@core.clip_text("日本語abc", 6), "日本..")
  assert_eq(@core.clip_text("abcdef", 6), "abcdef")
}

///|
test "reading remains paused when output arrives" {
  let start : @core.Reader = { page: 4, following: true }
  let paused = @core.reduce_reader(start, Move(-1), 5)
  assert_eq(paused, { page: 3, following: false })
  assert_eq(@core.reduce_reader(paused, Arrived, 10), paused)
  assert_eq(@core.reduce_reader(paused, ToggleFollow, 10), {
    page: 9,
    following: true,
  })
}

///|
test "pages are bounded when history shrinks" {
  assert_eq(@core.reduce_reader({ page: 5, following: false }, Arrived, 0), {
    page: 0,
    following: false,
  })
  assert_eq(@core.reduce_reader({ page: 0, following: true }, Move(-100), 8), {
    page: 0,
    following: false,
  })
}

///|
test "opening actions never dispatches a prompt" {
  let result = @core.navigation_json("output", "tap", 0, 3, 0, 6)
  guard @json.parse(result) is Object(fields) else { fail("expected object") }
  assert_eq(fields["effect"], Json::string("none"))
  assert_eq(fields["view"], Json::string("actions"))
}

///|
test "cancelling a confirmation never dispatches send or stop" {
  for view in ["draft", "stop"] {
    let result = @core.navigation_json(view, "back", 0, 3, 0, 6)
    guard @json.parse(result) is Object(fields) else { fail("expected object") }
    assert_eq(fields["effect"], Json::string("none"))
    assert_eq(fields["view"], Json::string("output"))
  }
}

///|
test "selection is bounded even when a session disappears" {
  let result = @core.navigation_json("sessions", "down", 5, 0, 0, 6)
  guard @json.parse(result) is Object(fields) else { fail("expected object") }
  assert_eq(fields["selection"], Json::number(0))
}
