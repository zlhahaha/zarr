///|
async fn S3Store::listing_once(
  self : S3Store,
  query : String,
  path : String,
) -> Result[Bytes, @store.AccessError] {
  let headers : Map[String, String] = match self.credentials {
    None => Map([])
    Some(credentials) => {
      guard amz_timestamp() is Some(stamp) else {
        return Err(@store.HeaderRejected(path))
      }
      guard signature_headers(
          credentials,
          self.region,
          self.bucket_url,
          None,
          None,
          stamp,
          query~,
        )
        is Some(headers) else {
        return Err(@store.HeaderRejected(path))
      }
      headers
    }
  }
  headers["Accept-Encoding"] = "identity"
  let (response, client) = @client_http.get_stream(
    "\{self.bucket_url}?\{query}",
    headers~,
  ) catch {
    _ => return Err(@store.Transport(path))
  }
  defer client.close()
  if response.code != 200 {
    return Err(
      match response.code {
        401 | 403 => @store.Authentication(path, response.code)
        412 => @store.Conflict(path)
        _ => @store.HttpStatus(path, response.code)
      },
    )
  }
  if response.headers.get("content-encoding") is Some(value) &&
    value.to_lower() != "identity" {
    return Err(@store.Protocol(path, "listing content-encoding"))
  }
  let bytes : Array[Byte] = []
  let limit = self.limits.max_metadata_bytes()
  for ;; {
    let data = client.read_some(max_len=32768) catch {
      _ => return Err(@store.Transport(path))
    }
    match data {
      None => return Ok(Bytes::from_array(bytes))
      Some(data) => {
        if data.length() > limit - bytes.length() {
          return Err(@store.LimitExceeded("listing response", path))
        }
        bytes.append(data.to_array()[:])
      }
    }
  }
}

///|
async fn S3Store::listing_page(
  self : S3Store,
  prefix : String,
  token : String?,
  path : String,
) -> Result[ListPage, @store.AccessError] {
  // Parameters are URI-encoded before sorting. These fixed parameter names
  // are emitted in canonical order; opaque tokens are encoded exactly once.
  let query = (match token {
      None => ""
      Some(token) => "continuation-token=\{uri_encode(token)}&"
    }) +
    "delimiter=%2F&encoding-type=url&list-type=2&max-keys=\{self.listing_page_size}&prefix=\{uri_encode(prefix)}"
  for attempt in 0..<2 {
    let result = match
      @async.with_timeout_opt(self.request_timeout_ms, async fn() {
        self.listing_once(query, path)
      }) {
      None => Err(@store.Timeout(path))
      Some(result) => result
    }
    match result {
      Ok(bytes) => {
        let raw = @utf8.decode(bytes[:]) catch {
          _ => return Err(@store.Protocol(path, "listing UTF-8"))
        }
        guard parse_list_page(raw, prefix, self.listing_page_size) is Some(page) else {
          return Err(@store.Protocol(path, "invalid ListObjectsV2 XML"))
        }
        return Ok(page)
      }
      Err(error) => {
        if attempt == 1 || !error.is_retryable() {
          return Err(error)
        }
        @async.sleep(50)
      }
    }
  }
  Err(@store.Transport(path))
}

///|
/// List explicit children with signed ListObjectsV2 delimiter pagination.
/// GetObject permission alone is insufficient: the principal needs ListBucket.
pub async fn S3Store::list_children_result(
  self : S3Store,
  path : String,
  max_nodes~ : Int32 = 4096,
) -> Result[Array[@hierarchy.Node], @store.AccessError] {
  if max_nodes <= 0 {
    return Err(@store.LimitExceeded("children", path))
  }
  let parent = match self.open_node_result(path) {
    Err(error) => return Err(error)
    Ok({ kind: @hierarchy.ArrayNode, .. }) => return Err(@store.NotGroup(path))
    Ok(node) => node
  }
  let logical_prefix = if path == "" { "" } else { "\{path}/" }
  let prefix = (if self.prefix == "" { "" } else { "\{self.prefix}/" }) +
    logical_prefix
  let candidates : Map[String, Bool] = Map([])
  let seen_tokens : Map[String, Bool] = Map([])
  let mut token : String? = None
  let mut entries = 0
  let mut finished = false
  for _ in 0..<self.max_listing_pages {
    let page = match self.listing_page(prefix, token, path) {
      Ok(page) => page
      Err(error) => return Err(error)
    }
    if page.entries > self.max_listing_entries - entries {
      return Err(@store.LimitExceeded("listing entries", path))
    }
    entries += page.entries
    for item in page.prefixes {
      if !item.has_prefix(prefix) ||
        !item.has_suffix("/") ||
        item.length() <= prefix.length() + 1 {
        return Err(
          @store.Protocol(path, "listing prefix outside requested directory"),
        )
      }
      let name = item[prefix.length():item.length() - 1].to_owned()
      let child = "\{logical_prefix}\{name}"
      if name.contains("/") || !@hierarchy.discovery_path(child) {
        return Err(@store.Protocol(path, "invalid child prefix"))
      }
      if !(parent.format == @metadata.V3 && name.has_prefix("__")) {
        candidates[child] = true
      }
    }
    match page.next {
      None => {
        finished = true
        break
      }
      Some(next) => {
        if seen_tokens.contains(next) {
          return Err(@store.Protocol(path, "repeated continuation token"))
        }
        seen_tokens[next] = true
        token = Some(next)
      }
    }
  }
  if !finished {
    return Err(@store.LimitExceeded("listing pages", path))
  }
  let paths : Array[String] = candidates.keys().collect()
  paths.sort_by((a, b) => a[:].lexical_compare(b))
  let nodes : Array[@hierarchy.Node] = []
  for child in paths {
    match self.open_node_result(child) {
      Ok(node) => {
        if nodes.length() >= max_nodes {
          return Err(@store.LimitExceeded("children", path))
        }
        nodes.push(node)
      }
      Err(@store.NotFound(_)) => ()
      Err(error) => return Err(error)
    }
  }
  Ok(nodes)
}

///|
pub async fn S3Store::walk_result(
  self : S3Store,
  path : String,
  max_nodes~ : Int32 = 4096,
  max_depth~ : Int32 = 64,
) -> Result[Array[@hierarchy.Node], @store.AccessError] {
  if max_nodes <= 0 || max_depth < 0 {
    return Err(@store.LimitExceeded("walk policy", path))
  }
  let queue = [(path, 0)]
  let nodes : Array[@hierarchy.Node] = []
  let mut position = 0
  while position < queue.length() {
    let (group, depth) = queue[position]
    position += 1
    let children = match self.list_children_result(group, max_nodes~) {
      Ok(children) => children
      Err(error) => return Err(error)
    }
    if children.length() > max_nodes - nodes.length() ||
      (depth >= max_depth && !children.is_empty()) {
      return Err(@store.LimitExceeded("walk", group))
    }
    for node in children {
      nodes.push(node)
      if node.kind == @hierarchy.GroupNode {
        queue.push((node.path, depth + 1))
      }
    }
  }
  Ok(nodes)
}
