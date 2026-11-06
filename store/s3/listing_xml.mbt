///|
/// Restricted S3 response parser: balanced elements, predefined/numeric
/// entities, fixed default namespace; no DTD, external entities or mixed text.
priv struct XmlNode {
  name : String
  text : String
  children : Array[XmlNode]
}

///|
fn uri_encode(value : String) -> String {
  let output = StringBuilder()
  for byte in @utf8.encode(value) {
    let n = byte.to_int()
    if (n >= 65 && n <= 90) ||
      (n >= 97 && n <= 122) ||
      (n >= 48 && n <= 57) ||
      n == 45 ||
      n == 95 ||
      n == 46 ||
      n == 126 {
      output.write_char(n.unsafe_to_char())
    } else {
      output.write_char('%')
      for part in [n >> 4, n & 15] {
        output.write_char(
          (if part < 10 { 48 + part } else { 55 + part }).unsafe_to_char(),
        )
      }
    }
  }
  output.to_string()
}

///|
fn uri_decode(value : String) -> String? {
  let bytes : Array[Byte] = []
  let encoded = @utf8.encode(value)
  let mut pos = 0
  while pos < encoded.length() {
    if encoded[pos] == b'%' {
      if pos + 2 >= encoded.length() {
        return None
      }
      let mut n = 0
      for at in [pos + 1, pos + 2] {
        let c = encoded[at].to_int()
        let digit = if c >= 48 && c <= 57 {
          c - 48
        } else if c >= 65 && c <= 70 {
          c - 55
        } else if c >= 97 && c <= 102 {
          c - 87
        } else {
          return None
        }
        n = n * 16 + digit
      }
      bytes.push(n.to_byte())
      pos += 3
    } else if encoded[pos] == b'+' {
      // MinIO uses form-style '+' for spaces in URL-encoded list fields.
      // Literal plus keys are percent-escaped (%2B), decoded above.
      bytes.push(b' ')
      pos += 1
    } else {
      bytes.push(encoded[pos])
      pos += 1
    }
  }
  Some(@utf8.decode(Bytes::from_array(bytes)[:]) catch { _ => return None })
}

///|
fn xml_text(raw : String) -> String? {
  for c in raw {
    let n = c.to_int()
    if (n < 32 && n != 9 && n != 10 && n != 13) || n == 65534 || n == 65535 {
      return None
    }
  }
  if raw.contains("]]>") {
    return None
  }
  let output = StringBuilder()
  let mut rest = raw[:]
  while rest.split_once("&") is Some((before, after)) {
    output.write_string(before.to_owned())
    guard after.split_once(";") is Some((entity, tail)) else { return None }
    match entity {
      "amp" => output.write_char('&')
      "lt" => output.write_char('<')
      "gt" => output.write_char('>')
      "quot" => output.write_char('"')
      "apos" => output.write_char('\'')
      _ => {
        let digits = if entity.has_prefix("#x") {
          entity[2:]
        } else if entity.has_prefix("#") {
          entity[1:]
        } else {
          return None
        }
        if digits.is_empty() {
          return None
        }
        for c in digits {
          let v = c.to_int()
          if !(v >= 48 && v <= 57) &&
            !(entity.has_prefix("#x") &&
            ((v >= 65 && v <= 70) || (v >= 97 && v <= 102))) {
            return None
          }
        }
        let n = if entity.has_prefix("#x") {
          @string.parse_int(entity[2:], base=16) catch {
            _ => return None
          }
        } else if entity.has_prefix("#") {
          @string.parse_int(entity[1:]) catch {
            _ => return None
          }
        } else {
          return None
        }
        if n < 0 ||
          n > 1114111 ||
          n == 65534 ||
          n == 65535 ||
          (n >= 55296 && n <= 57343) ||
          (n < 32 && n != 9 && n != 10 && n != 13) {
          return None
        }
        output.write_char(n.unsafe_to_char())
      }
    }
    rest = tail
  }
  output.write_string(rest.to_owned())
  Some(output.to_string())
}

///|
fn xml_node(
  input : String,
  position : Ref[Int32],
  depth : Int32,
  count : Ref[Int32],
) -> XmlNode? {
  if depth > 16 ||
    count.val >= 32768 ||
    position.val >= input.length() ||
    input.code_unit_at(position.val).to_int() != 60 {
    return None
  }
  let start = position.val + 1
  let mut end = start
  while end < input.length() && input.code_unit_at(end).to_int() != 62 {
    end += 1
  }
  if end == input.length() {
    return None
  }
  let header = input[start:end].trim().to_owned()
  let empty = header.has_suffix("/")
  let header = if empty {
    header[:header.length() - 1].trim().to_owned()
  } else {
    header
  }
  let name = if depth == 0 {
    if header == "ListBucketResult" ||
      header ==
      "ListBucketResult xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\"" ||
      header ==
      "ListBucketResult xmlns='http://s3.amazonaws.com/doc/2006-03-01/'" {
      "ListBucketResult"
    } else {
      return None
    }
  } else {
    if header == "" {
      return None
    }
    for c in header {
      let n = c.to_int()
      if !((n >= 65 && n <= 90) || (n >= 97 && n <= 122) || (n >= 48 && n <= 57)) {
        return None
      }
    }
    header
  }
  position.val = end + 1
  count.val += 1
  let children : Array[XmlNode] = []
  if empty {
    return Some({ name, text: "", children, })
  }
  let text = StringBuilder()
  while position.val < input.length() {
    let text_start = position.val
    while position.val < input.length() &&
          input.code_unit_at(position.val).to_int() != 60 {
      position.val += 1
    }
    text.write_string(input[text_start:position.val].to_owned())
    if position.val >= input.length() {
      return None
    }
    if input[position.val:].has_prefix("</") {
      let close_start = position.val + 2
      let mut close_end = close_start
      while close_end < input.length() &&
            input.code_unit_at(close_end).to_int() != 62 {
        close_end += 1
      }
      if close_end == input.length() ||
        input[close_start:close_end].trim() != name {
        return None
      }
      position.val = close_end + 1
      let raw = text.to_string()
      if !children.is_empty() && raw.trim() != "" {
        return None
      }
      guard xml_text(raw) is Some(decoded) else { return None }
      return Some({ name, text: decoded, children, })
    }
    guard xml_node(input, position, depth + 1, count) is Some(child) else {
      return None
    }
    children.push(child)
  }
  None
}

///|
fn xml_field(node : XmlNode, name : String) -> String? {
  let mut value = None
  for child in node.children {
    if child.name == name {
      if value is Some(_) || !child.children.is_empty() {
        return None
      }
      value = Some(child.text)
    }
  }
  value
}

///|
priv struct ListPage {
  prefixes : Array[String]
  entries : Int32
  next : String?
}

///|
fn parse_list_page(
  raw : String,
  prefix : String,
  page_size : Int32,
) -> ListPage? {
  let raw = raw.trim().to_owned()
  let raw = if raw.has_prefix("<?xml ") {
    guard raw.split_once("?>") is Some((_, tail)) else { return None }
    tail.trim().to_owned()
  } else {
    raw
  }
  let position = Ref(0)
  guard xml_node(raw, position, 0, Ref(0)) is Some(root) else { return None }
  if position.val != raw.length() ||
    xml_field(root, "EncodingType") != Some("url") {
    return None
  }
  guard xml_field(root, "Prefix") is Some(encoded_prefix) else { return None }
  if uri_decode(encoded_prefix) != Some(prefix) {
    return None
  }
  guard xml_field(root, "Delimiter") is Some(delimiter) else { return None }
  if uri_decode(delimiter) != Some("/") {
    return None
  }
  guard xml_field(root, "KeyCount") is Some(count_raw) else { return None }
  let count = @string.parse_int(count_raw) catch { _ => return None }
  if count < 0 || count > page_size {
    return None
  }
  let prefixes : Array[String] = []
  let mut observed = 0
  for child in root.children {
    if child.name == "CommonPrefixes" {
      guard xml_field(child, "Prefix") is Some(value) else { return None }
      guard uri_decode(value) is Some(decoded) else { return None }
      prefixes.push(decoded)
      observed += 1
    } else if child.name == "Contents" {
      guard xml_field(child, "Key") is Some(value) else { return None }
      guard uri_decode(value) is Some(key) else { return None }
      if !key.has_prefix(prefix) {
        return None
      }
      observed += 1
    }
  }
  if observed != count {
    return None
  }
  let next = match xml_field(root, "IsTruncated") {
    Some("false") => None
    Some("true") => {
      guard xml_field(root, "NextContinuationToken") is Some(token) else {
        return None
      }
      if token == "" || count == 0 {
        return None
      }
      Some(token)
    }
    _ => return None
  }
  Some({ prefixes, entries: count, next, })
}
