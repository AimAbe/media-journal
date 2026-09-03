// RAWG.io API — search + details URL builders and response normalizers.
// https://api.rawg.io/docs/

var BASE_URL = "https://api.rawg.io/api"

function searchUrl(apiKey, query, pageSize) {
  return BASE_URL + "/games"
    + "?key=" + encodeURIComponent(apiKey)
    + "&search=" + encodeURIComponent(query)
    + "&page_size=" + encodeURIComponent(pageSize || 10)
}

function detailsUrl(apiKey, id) {
  return BASE_URL + "/games/" + encodeURIComponent(id) + "?key=" + encodeURIComponent(apiKey)
}

// Returns a number (so Dataview's `WHERE year = 2026` compares numerically)
// or null when nothing usable is available.
function yearFromReleased(released) {
  if (!released || released.length < 4) return null
  var year = parseInt(released.slice(0, 4), 10)
  return isNaN(year) ? null : year
}

function joinNames(list, keyPath) {
  if (!Array.isArray(list)) return ""
  var names = []
  for (var i = 0; i < list.length; i++) {
    var item = list[i]
    var value = keyPath ? (item && item[keyPath] && item[keyPath].name) : (item && item.name)
    if (value) names.push(value)
  }
  return names.join(", ")
}

// One entry from the /games search endpoint's `results[]`.
function normalizeSearchHit(hit) {
  return {
    id: hit.id,
    title: hit.name || "",
    year: yearFromReleased(hit.released),
    platforms: joinNames(hit.platforms, "platform"),
    backgroundImage: hit.background_image || "",
    rawgRating: typeof hit.rating === "number" ? hit.rating : null
  }
}

function parseSearchResults(rawJson) {
  var data = JSON.parse(rawJson)
  var results = Array.isArray(data.results) ? data.results : []
  var out = []
  for (var i = 0; i < results.length; i++) out.push(normalizeSearchHit(results[i]))
  return out
}

// /games/{id} — adds developer, which the search endpoint doesn't return.
function parseDetails(rawJson) {
  var data = JSON.parse(rawJson)
  return {
    id: data.id,
    title: data.name || "",
    year: yearFromReleased(data.released),
    developer: joinNames(data.developers, null),
    platforms: joinNames(data.platforms, "platform"),
    backgroundImage: data.background_image || ""
  }
}
