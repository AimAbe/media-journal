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
