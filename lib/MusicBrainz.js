// MusicBrainz search API — no key required, but the API's usage policy
// requires a descriptive User-Agent identifying the app (see contactHeader
// below); Service.qml passes it on every curl call, not this file, since
// it comes from config rather than being a MusicBrainz-specific constant.
// https://musicbrainz.org/doc/MusicBrainz_API
//
// Like Open Library, release-group search already carries what a log entry
// needs (title, artist, year) — format/label are the physical/digital
// edition the *listener* has, which varies by release and isn't worth an
// extra fetch, so (same as book.format) they're user-entered, not fetched.

var BASE_URL = "https://musicbrainz.org/ws/2"

function searchUrl(query, limit) {
  return BASE_URL + "/release-group/"
    + "?query=" + encodeURIComponent(query)
    + "&fmt=json"
    + "&limit=" + encodeURIComponent(limit || 10)
}

// Returns a number (so Dataview's `WHERE year = 2026` compares numerically)
// or null when nothing usable is available.
function yearFromDate(dateStr) {
  if (!dateStr || dateStr.length < 4) return null
  var year = parseInt(dateStr.slice(0, 4), 10)
  return isNaN(year) ? null : year
}

function joinArtists(artistCredit) {
  if (!Array.isArray(artistCredit)) return ""
  var names = []
  for (var i = 0; i < artistCredit.length; i++) {
    var credit = artistCredit[i]
    if (credit && credit.name) names.push(credit.name)
  }
  return names.join(", ")
}

// One entry from `release-groups[]`.
function normalizeSearchHit(rg) {
  return {
    id: rg.id,
    title: rg.title || "",
    artist: joinArtists(rg["artist-credit"]),
    year: yearFromDate(rg["first-release-date"]),
    primaryType: rg["primary-type"] || ""
  }
}

function parseSearchResults(rawJson) {
  var data = JSON.parse(rawJson)
  var groups = Array.isArray(data["release-groups"]) ? data["release-groups"] : []
  var out = []
  for (var i = 0; i < groups.length; i++) out.push(normalizeSearchHit(groups[i]))
  return out
}
