///|
/// Conservative display-cell width. Combining marks occupy no additional cell;
/// CJK, full-width and emoji code points occupy two. Firmware glyph availability
/// remains device-owned; this function never slices UTF-16 surrogate pairs.
fn cell_width(char : Char) -> Int {
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
    (code >= 0x1f300 && code <= 0x1faff) {
    2
  } else {
    1
  }
}

///|
/// Wrap plain text while preserving blank lines and Unicode code points.
/// Bounds are explicit so the core is independent of any particular device.
pub fn wrap_text(text : String, columns : Int) -> Array[String] {
  let limit = if columns < 2 { 2 } else { columns }
  let lines : Array[String] = []
  let mut row = ""
  let mut width = 0
  for char in text.iter() {
    if char == '\n' {
      lines.push(row)
      row = ""
      width = 0
    } else {
      let size = cell_width(char)
      if width + size > limit {
        lines.push(row)
        row = ""
        width = 0
      }
      row += char.to_string()
      width += size
    }
  }
  lines.push(row)
  lines
}

///|
/// Clip a heading to its display-cell budget; the marker also consumes cells.
pub fn clip_text(text : String, columns : Int) -> String {
  let limit = if columns < 2 { 2 } else { columns }
  let mut total = 0
  for char in text.iter() {
    total += cell_width(char)
  }
  if total <= limit {
    return text
  }
  let mut result = ""
  let mut width = 0
  for char in text.iter() {
    let size = cell_width(char)
    if width + size > limit - 2 {
      break
    }
    result += char.to_string()
    width += size
  }
  result + ".."
}

///|
/// JSON is the only FFI boundary: callers pass an array of strings and receive
/// an array of pages. Invalid input safely produces an empty-page placeholder.
pub fn paginate_json(input : String, columns : Int, rows : Int) -> String {
  let lines : Array[String] = []
  let value = @json.parse(input) catch { _ => Json::null() }
  match value {
    Array(items) =>
      for item in items {
        if item is String(text) {
          for row in wrap_text(text, columns) {
            lines.push(row)
          }
        }
      }
    _ => ()
  }
  let page_rows = if rows < 1 { 1 } else { rows }
  let pages : Array[String] = []
  let mut page = ""
  for index, line in lines {
    if index % page_rows == 0 && index > 0 {
      pages.push(page)
      page = ""
    }
    if index % page_rows != 0 {
      page += "\n"
    }
    page += line
  }
  if lines.length() > 0 {
    pages.push(page)
  }
  if pages.is_empty() {
    pages.push("")
  }
  pages.to_json().stringify()
}
