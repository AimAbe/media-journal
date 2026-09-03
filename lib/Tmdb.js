// TMDB API — search + details URL builders and response normalizers.
// https://developer.themoviedb.org/reference/intro/getting-started

var BASE_URL = "https://api.themoviedb.org/3"

function searchUrl(apiKey, query) {
  return BASE_URL + "/search/movie"
    + "?api_key=" + encodeURIComponent(apiKey)
    + "&query=" + encodeURIComponent(query)
    + "&include_adult=false"
}

// append_to_response=credits gets the crew list (for director) in the same
// request as the movie details, instead of a separate /movie/{id}/credits call.
function detailsUrl(apiKey, id) {
  return BASE_URL + "/movie/" + encodeURIComponent(id)
    + "?api_key=" + encodeURIComponent(apiKey)
    + "&append_to_response=credits"
}

// Returns a number (so Dataview's `WHERE year = 2026` compares numerically)
// or null when nothing usable is available.
function yearFromDate(dateStr) {
  if (!dateStr || dateStr.length < 4) return null
  var year = parseInt(dateStr.slice(0, 4), 10)
  return isNaN(year) ? null : year
}

function directorNames(crew) {
  if (!Array.isArray(crew)) return ""
  var names = []
  for (var i = 0; i < crew.length; i++) {
    var member = crew[i]
    if (member && member.job === "Director" && member.name) names.push(member.name)
  }
  return names.join(", ")
}

// One entry from the /search/movie endpoint's `results[]`.
function normalizeSearchHit(hit) {
  return {
    id: hit.id,
    title: hit.title || "",
    year: yearFromDate(hit.release_date),
    overview: hit.overview || "",
    posterPath: hit.poster_path || "",
    tmdbRating: typeof hit.vote_average === "number" ? hit.vote_average : null
  }
}

function parseSearchResults(rawJson) {
  var data = JSON.parse(rawJson)
  var results = Array.isArray(data.results) ? data.results : []
  var out = []
  for (var i = 0; i < results.length; i++) out.push(normalizeSearchHit(results[i]))
  return out
}

// /movie/{id}?append_to_response=credits — adds director, which the search
// endpoint doesn't return, plus runtime.
function parseDetails(rawJson) {
  var data = JSON.parse(rawJson)
  return {
    id: data.id,
    title: data.title || "",
    year: yearFromDate(data.release_date),
    director: directorNames(data.credits && data.credits.crew),
    runtime: typeof data.runtime === "number" && data.runtime > 0 ? data.runtime : null,
    posterPath: data.poster_path || ""
  }
}
