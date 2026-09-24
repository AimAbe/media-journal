// Portrait box art for games. RAWG only has landscape art (screenshots and
// banners), but it knows each game's Steam store page, and Steam's public
// store-browse API (no key) returns the exact path of the game's 600x900
// library capsule. Newer games keep that file under a hashed directory, so
// the old fixed URL pattern isn't enough.

var ASSET_BASE = "https://shared.akamai.steamstatic.com/store_item_assets/"

// From the response of RAWG's /games/<id>/stores endpoint.
function steamAppIdFromRawgStores(rawJson) {
  var data = JSON.parse(rawJson)
  var results = Array.isArray(data.results) ? data.results : []
  for (var i = 0; i < results.length; i++) {
    var m = /store\.steampowered\.com\/app\/(\d+)/.exec(String(results[i].url || ""))
    if (m) return Number(m[1])
  }
  return null
}

function itemsUrl(appId) {
  var input = {
    ids: [{ appid: appId }],
    context: { language: "english", country_code: "US" },
    data_request: { include_assets: true }
  }
  return "https://api.steampowered.com/IStoreBrowseService/GetItems/v1?input_json="
    + encodeURIComponent(JSON.stringify(input))
}

// -> the 2x (600x900) portrait capsule URL, or "" if the game has none.
function capsuleUrlFromItems(rawJson) {
  var data = JSON.parse(rawJson)
  var items = data.response && Array.isArray(data.response.store_items) ? data.response.store_items : []
  var assets = items.length ? items[0].assets : null
  if (!assets || !assets.asset_url_format) return ""
  var file = assets.library_capsule_2x || assets.library_capsule
  if (!file) return ""
  return ASSET_BASE + String(assets.asset_url_format).replace("${FILENAME}", file)
}
