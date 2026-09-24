// Comic Vine search API — needs a key (like RAWG/TMDB) and, unlike either
// of those, also blocks generic/bot-like User-Agents outright (Service.qml
// sends the same descriptive one it uses for MusicBrainz).
// https://comicvine.gamespot.com/api/documentation
//
// Searches the `volume` resource — a series/run (e.g. "Saga", "Sandman"),
// not a single issue. A volume's search result already carries start_year,
// publisher, and issue count, so — same as Open Library/MusicBrainz —
// there's no details fetch. It does NOT carry writer/artist: those are
// per-issue creator credits that Comic Vine only exposes on individual
// issues and that legitimately change across a long-running volume, so
// (same call as book.format / music.format+label) they're user-entered
// rather than fetched.

var BASE_URL = "https://comicvine.gamespot.com/api"

function searchUrl(apiKey, query, limit) {
  return BASE_URL + "/search/"
    + "?api_key=" + encodeURIComponent(apiKey)
    + "&format=json"
    + "&resources=volume"
    + "&query=" + encodeURIComponent(query)
    + "&limit=" + encodeURIComponent(limit || 10)
}

// start_year comes back as a numeric-looking string (sometimes null).
function yearFromStartYear(startYear) {
  if (!startYear) return null
  var year = parseInt(String(startYear).slice(0, 4), 10)
  return isNaN(year) ? null : year
}

// One entry from `results[]`.
function normalizeSearchHit(hit) {
  return {
    id: hit.id,
    title: hit.name || "",
    year: yearFromStartYear(hit.start_year),
    publisher: hit.publisher && hit.publisher.name ? hit.publisher.name : "",
    issueCount: typeof hit.count_of_issues === "number" ? hit.count_of_issues : null,
    coverUrl: hit.image ? (hit.image.small_url || hit.image.medium_url || hit.image.thumb_url || "") : ""
  }
}

function parseSearchResults(rawJson) {
  var data = JSON.parse(rawJson)
  // Comic Vine's own status_code (1 == OK); a bad key still returns HTTP 200.
  if (data.status_code !== 1) {
    throw new Error(data.error || ("Comic Vine status_code " + data.status_code))
  }
  var results = Array.isArray(data.results) ? data.results : []
  var out = []
  for (var i = 0; i < results.length; i++) out.push(normalizeSearchHit(results[i]))
  return out
}
