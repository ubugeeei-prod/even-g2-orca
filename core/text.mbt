///|
/// Display-cell width of a code point. Combining marks take no cell; CJK,
/// full-width and emoji take two. Glyph coverage itself is device-owned.
pub fn cell_width(char : Char) -> Int {
  let code = char.to_int()
  if (code >= 0x0300 && code <= 0x036f) ||
    (code >= 0xfe00 && code <= 0xfe0f) ||
    code == 0x200d {
    0
  } else if (code >= 0x1100 && code <= 0x115f) ||
    (code >= 0x2e80 && code <= 0xa4cf) ||
    (code >= 0xac00 && code <= 0xd7a3) ||
    (code >= 0xf900 && code <= 0xfaff) ||
    (code >= 0xfe10 && code <= 0xfe6f) ||
    (code >= 0xff01 && code <= 0xff60) ||
    (code >= 0xffe0 && code <= 0xffe6) ||
    (code >= 0x1f300 && code <= 0x1faff) ||
    (code >= 0x20000 && code <= 0x3fffd) {
    2
  } else {
    1
  }
}

///|
/// Total display cells of a string.
pub fn text_width(text : String) -> Int {
  let mut total = 0
  for char in text {
    total += cell_width(char)
  }
  total
}

///|
/// Remove ANSI CSI / OSC sequences and nonprinting controls from terminal text.
/// Tabs become four spaces; newlines are kept.
pub fn clean_terminal_text(text : String) -> String {
  let out = StringBuilder::new()
  let chars = text.to_array()
  let n = chars.length()
  let mut i = 0
  while i < n {
    let c = chars[i]
    let code = c.to_int()
    if code == 0x1b {
      if i + 1 >= n {
        break
      }
      let next = chars[i + 1]
      if next == '[' {
        // CSI: parameters and intermediates, then a final byte in @..~
        let mut j = i + 2
        while j < n {
          let k = chars[j].to_int()
          if k >= 0x40 && k <= 0x7e {
            break
          }
          j += 1
        }
        i = j + 1
      } else if next == ']' {
        // OSC: terminated by BEL or ESC \
        let mut j = i + 2
        while j < n {
          if chars[j].to_int() == 0x07 {
            j += 1
            break
          }
          if chars[j].to_int() == 0x1b && j + 1 < n && chars[j + 1] == '\\' {
            j += 2
            break
          }
          j += 1
        }
        i = j
      } else {
        i += 2
      }
    } else if c == '\t' {
      out.write_string("    ")
      i += 1
    } else if c == '\n' {
      out.write_char(c)
      i += 1
    } else if code < 0x20 || code == 0x7f || (code >= 0x80 && code < 0xa0) {
      i += 1
    } else {
      out.write_char(c)
      i += 1
    }
  }
  out.to_string()
}

///|
/// Drop trailing spaces, which terminal screens pad lines with.
pub fn trim_end_spaces(text : String) -> String {
  let chars = text.to_array()
  let mut end = chars.length()
  while end > 0 && chars[end - 1] == ' ' {
    end -= 1
  }
  if end == chars.length() {
    text
  } else {
    String::from_array(chars[:end])
  }
}

///|
/// Wrap text to a cell budget, keeping blank lines and never splitting a code
/// point.
pub fn wrap_text(text : String, columns : Int) -> Array[String] {
  let limit = if columns < 2 { 2 } else { columns }
  let lines : Array[String] = []
  let row = StringBuilder::new()
  let mut width = 0
  for char in text {
    if char == '\n' {
      lines.push(row.to_string())
      row.reset()
      width = 0
    } else {
      let size = cell_width(char)
      if width + size > limit {
        lines.push(row.to_string())
        row.reset()
        width = 0
      }
      row.write_char(char)
      width += size
    }
  }
  lines.push(row.to_string())
  lines
}

///|
/// Wrap every line and flatten.
pub fn wrap_lines(lines : Array[String], columns : Int) -> Array[String] {
  let out : Array[String] = []
  for line in lines {
    for row in wrap_text(line, columns) {
      out.push(row)
    }
  }
  out
}

///|
/// Split rows into pages of at most `rows`; always returns at least one page.
pub fn paginate(lines : Array[String], rows : Int) -> Array[Array[String]] {
  let size = if rows < 1 { 1 } else { rows }
  let pages : Array[Array[String]] = []
  let mut i = 0
  while i < lines.length() {
    let end = if i + size > lines.length() { lines.length() } else { i + size }
    pages.push(lines[i:end].to_owned())
    i = end
  }
  if pages.is_empty() {
    pages.push([])
  }
  pages
}

///|
/// Clip to a cell budget; the ".." marker consumes two cells.
pub fn clip_text(text : String, columns : Int) -> String {
  let limit = if columns < 3 { 3 } else { columns }
  if text_width(text) <= limit {
    return text
  }
  let out = StringBuilder::new()
  let mut width = 0
  for char in text {
    let size = cell_width(char)
    if width + size > limit - 2 {
      break
    }
    out.write_char(char)
    width += size
  }
  out.write_string("..")
  out.to_string()
}

///|
/// Remove blank rows at the end of a terminal screen.
pub fn drop_trailing_blank(lines : Array[String]) -> Array[String] {
  let mut end = lines.length()
  while end > 0 && lines[end - 1].is_empty() {
    end -= 1
  }
  lines[:end].to_owned()
}

///|
/// Last path segment, without trailing separators.
pub fn basename(path : String) -> String {
  let parts = path.split("/").map(fn(s) { s.to_owned() }).to_array()
  let mut i = parts.length() - 1
  while i >= 0 && parts[i].is_empty() {
    i -= 1
  }
  if i < 0 {
    ""
  } else {
    parts[i]
  }
}

///|
/// Terminal UIs draw full-width rules; on the glasses a short marker is enough.
pub fn display_line(line : String) -> String {
  if line.length() < 8 {
    return line
  }
  for c in line {
    if !(c is ('─' | '━' | '-' | '═' | '—' | ' ')) {
      return line
    }
  }
  "--------"
}

///|
/// Like `paginate`, but anchored at the end so the newest page is full and
/// only the oldest page may be short.
pub fn paginate_from_end(
  lines : Array[String],
  rows : Int,
) -> Array[Array[String]] {
  let size = if rows < 1 { 1 } else { rows }
  let pages : Array[Array[String]] = []
  let mut end = lines.length()
  while end > 0 {
    let start = if end - size < 0 { 0 } else { end - size }
    pages.push(lines[start:end].to_owned())
    end = start
  }
  pages.rev_in_place()
  if pages.is_empty() {
    pages.push([])
  }
  pages
}
