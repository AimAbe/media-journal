// Open Library search API — no key required, and unlike RAWG/TMDB the
// search endpoint already carries author + first-publish-year + page count,
// so there's no separate "details" fetch: search -> select -> save.
// https://openlibrary.org/dev/docs/api/search

var BASE_URL = "https://openlibrary.org"

// Restricting `fields` keeps the response small — search can return
// thousands of edition keys per doc otherwise.
var SEARCH_FIELDS = "key,title,author_name,first_publish_year,number_of_pages_median,cover_i"

function searchUrl(query, limit) {
  return BASE_URL + "/search.json"
    + "?q=" + encodeURIComponent(query)
    + "&limit=" + encodeURIComponent(limit || 10)
    + "&fields=" + SEARCH_FIELDS
}

function joinAuthors(authorNames) {
  return Array.isArray(authorNames) ? authorNames.join(", ") : ""
}

// One entry from `docs[]`. `key` (e.g. "/works/OL21745884W") is the stable
// id — Open Library doesn't hand out small integer ids like RAWG/TMDB.
function normalizeSearchHit(doc) {
  return {
    key: doc.key,
    title: doc.title || "",
    author: joinAuthors(doc.author_name),
    year: typeof doc.first_publish_year === "number" ? doc.first_publish_year : null,
    pages: typeof doc.number_of_pages_median === "number" ? doc.number_of_pages_median : null,
    coverId: typeof doc.cover_i === "number" ? doc.cover_i : null,
    coverUrl: typeof doc.cover_i === "number" ? "https://covers.openlibrary.org/b/id/" + doc.cover_i + "-M.jpg" : ""
  }
}

function parseSearchResults(rawJson) {
  var data = JSON.parse(rawJson)
  var docs = Array.isArray(data.docs) ? data.docs : []
  var out = []
  for (var i = 0; i < docs.length; i++) out.push(normalizeSearchHit(docs[i]))
  return out
}
