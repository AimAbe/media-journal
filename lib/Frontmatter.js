// Shared markdown note builder. Used by every media type (game, film, book,
// comic, music) — keep this file free of any one API's shape.

// uniqueId (optional): the source API's own id/key for this entry (RAWG's
// numeric id, an Open Library work key, a MusicBrainz MBID, ...). A title
// with no ASCII letters or digits — a non-Latin script, or symbols only —
// collapses to nothing here, and without a tiebreaker every such entry of
// the same media type would land on the same "untitled.md", silently
// overwriting one another. Falling back to the id instead of a bare
// "untitled" keeps them distinct; only bare "untitled" when there's truly
// no id to fall back on.
function slugify(title, uniqueId) {
  var s = String(title || "").toLowerCase().trim()
  s = s.replace(/[^a-z0-9]+/g, "-")
  s = s.replace(/^-+|-+$/g, "")
  if (s) return s

  var idSlug = String(uniqueId || "").toLowerCase().trim()
  idSlug = idSlug.replace(/[^a-z0-9]+/g, "-")
  idSlug = idSlug.replace(/^-+|-+$/g, "")
  return idSlug ? "untitled-" + idSlug : "untitled"
}

function today() {
  var d = new Date()
  var mm = String(d.getMonth() + 1).padStart(2, "0")
  var dd = String(d.getDate()).padStart(2, "0")
  return d.getFullYear() + "-" + mm + "-" + dd
}

// True for values that should be dropped from frontmatter rather than
// written out as `key: null` / `key: ""`.
function isEmpty(value) {
  if (value === null || value === undefined) return true
  if (typeof value === "string") return value.trim() === ""
  if (Array.isArray(value)) return value.length === 0
  return false
}

// YAML flow scalar for a single value: numbers/booleans pass through,
// strings get double-quoted (safe superset of what YAML needs here since
// titles/reviews can contain colons, hashes, and quotes of their own).
function yamlScalar(value) {
  if (typeof value === "number" || typeof value === "boolean") return String(value)
  return JSON.stringify(String(value))
}

function yamlValue(value) {
  if (Array.isArray(value)) {
    var items = []
    for (var i = 0; i < value.length; i++) items.push(yamlScalar(value[i]))
    return "[" + items.join(", ") + "]"
  }
  return yamlScalar(value)
}

// fields: plain object, insertion order is preserved (JS objects keep
// string-key insertion order) and drives the frontmatter's line order.
function buildFrontmatter(fields) {
  var lines = ["---"]
  for (var key in fields) {
    if (!Object.prototype.hasOwnProperty.call(fields, key)) continue
    var value = fields[key]
    if (isEmpty(value)) continue
    lines.push(key + ": " + yamlValue(value))
  }
  lines.push("---")
  return lines.join("\n")
}

// fields: frontmatter object (must include `title`). body: free-form
// markdown (the review) placed under a heading, not in the frontmatter —
// keeps Dataview queries simple and lets reviews use real markdown.
function buildNote(fields, body) {
  var out = buildFrontmatter(fields) + "\n\n# " + String(fields.title || "Untitled")
  var trimmedBody = String(body || "").trim()
  if (trimmedBody) out += "\n\n" + trimmedBody
  return out + "\n"
}

// ------------------------------------------------------------ reading back
//
// Notes are read back so the menu can list past entries and edit them in
// place. They start out exactly as buildNote() wrote them, but the user may
// have edited them in Obsidian since, so parsing is forgiving and updating
// only touches the keys it is told to change. Every other frontmatter line,
// including ones this plugin never wrote, is kept byte for byte and in order.

// One frontmatter value as written by yamlScalar()/yamlValue() (JSON-shaped),
// or plain YAML typed by hand (`status: playing`, `rating: 4`, 'quoted').
function parseScalar(raw) {
  var s = String(raw || "").trim()
  if (s === "") return ""
  try { return JSON.parse(s) } catch (e) {}
  if (s.length >= 2 && s[0] === "'" && s[s.length - 1] === "'")
    return s.slice(1, -1).replace(/''/g, "'")
  return s
}

function splitNote(text) {
  text = String(text || "")
  var m = /^---\r?\n([\s\S]*?)\r?\n---[ \t]*(?:\r?\n|$)/.exec(text)
  if (!m) return { fmLines: [], body: text, hasFrontmatter: false }
  return { fmLines: m[1].split(/\r?\n/), body: text.slice(m[0].length), hasFrontmatter: true }
}

// [{key, lines}]: continuation lines (a block list, a wrapped string, a
// comment) stay attached to the key above them so nothing gets reordered.
function groupFrontmatter(fmLines) {
  var groups = []
  var current = { key: null, lines: [] }
  for (var i = 0; i < fmLines.length; i++) {
    var line = fmLines[i]
    var m = /^([A-Za-z0-9_-]+):(.*)$/.exec(line)
    if (m) {
      if (current.key !== null || current.lines.length) groups.push(current)
      current = { key: m[1], lines: [line] }
    } else {
      current.lines.push(line)
    }
  }
  if (current.key !== null || current.lines.length) groups.push(current)
  return groups
}

function groupValue(group) {
  var first = group.lines[0].slice(group.key.length + 1)
  if (group.lines.length === 1 || first.trim() !== "") return parseScalar(first)
  // `key:` followed by `  - item` lines: a block list.
  var items = []
  for (var i = 1; i < group.lines.length; i++) {
    var m = /^\s*-\s+(.*)$/.exec(group.lines[i])
    if (m) items.push(parseScalar(m[1]))
  }
  return items
}

// The body is "# Title" then the review. Anything above the heading is
// unusual enough that it's treated as part of the review.
function splitBody(body) {
  var m = /^\s*(#[ \t]+[^\r\n]*)(?:\r?\n|$)/.exec(body)
  if (!m) return { headingLine: "", review: String(body).trim() }
  return { headingLine: m[1], review: body.slice(m[0].length).trim() }
}

// -> { fields: {key: value}, heading: "Title", review: "..." }
function parseNote(text) {
  var parts = splitNote(text)
  var groups = groupFrontmatter(parts.fmLines)
  var fields = {}
  for (var i = 0; i < groups.length; i++)
    if (groups[i].key !== null) fields[groups[i].key] = groupValue(groups[i])
  var body = splitBody(parts.body)
  return {
    fields: fields,
    heading: body.headingLine.replace(/^#[ \t]+/, "").trim(),
    review: body.review
  }
}

// changes: {key: newValue}. An empty value (see isEmpty) removes the key;
// a key the note doesn't have yet is appended. review replaces the text
// under the heading; the heading line itself is kept.
function updateNote(text, changes, review) {
  var parts = splitNote(text)
  var groups = groupFrontmatter(parts.fmLines)

  for (var key in changes) {
    if (!Object.prototype.hasOwnProperty.call(changes, key)) continue
    var value = changes[key]
    var idx = -1
    for (var i = 0; i < groups.length; i++) if (groups[i].key === key) { idx = i; break }
    // Lines under an inline `key: value` are comments or stray text, not
    // part of the value, so they survive; under a bare `key:` they're the
    // block-list value itself and get replaced along with it.
    var kept = []
    if (idx >= 0 && groups[idx].lines[0].slice(key.length + 1).trim() !== "")
      kept = groups[idx].lines.slice(1)
    if (isEmpty(value)) {
      if (idx >= 0) groups[idx] = { key: null, lines: kept }
    } else if (idx >= 0) {
      groups[idx] = { key: key, lines: [key + ": " + yamlValue(value)].concat(kept) }
    } else {
      groups.push({ key: key, lines: [key + ": " + yamlValue(value)] })
    }
  }

  var fmLines = []
  for (var g = 0; g < groups.length; g++) fmLines = fmLines.concat(groups[g].lines)

  var body = splitBody(parts.body)
  var headingLine = body.headingLine
  if (!headingLine) {
    var titleGroup = null
    for (var t = 0; t < groups.length; t++) if (groups[t].key === "title") titleGroup = groups[t]
    headingLine = "# " + String((titleGroup && groupValue(titleGroup)) || "Untitled")
  }

  var out = "---\n" + fmLines.join("\n") + "\n---\n\n" + headingLine
  var trimmedReview = String(review || "").trim()
  if (trimmedReview) out += "\n\n" + trimmedReview
  return out + "\n"
}
