import QtQuick
import Quickshell
import Quickshell.Io
import "lib/Frontmatter.js" as Frontmatter
import "lib/Rawg.js" as Rawg
import "lib/Tmdb.js" as Tmdb
import "lib/OpenLibrary.js" as OpenLibrary
import "lib/MusicBrainz.js" as MusicBrainz
import "lib/ComicVine.js" as ComicVine

// Media Journal service. Owns config, per-media search + markdown writing.
// A menu/bar-widget in the same shell process talks to this directly via
// serviceFor("aimabe.mediajournal") and binds to its reactive properties;
// the IpcHandler below exists for external callers (keybindings, testing)
// and mirrors the same operations behind typed string args.
//
// This file covers all five media types from plan.md: RAWG (games), TMDB
// (films), Open Library (books), MusicBrainz (music), Comic Vine (comics).
// Each follows the same shape: a lib/<Api>.js normalizer, a search (+
// details, if the search endpoint is thin) Process, and a writeXEntry()
// that hands off to the shared saveEntry(). Open Library's, MusicBrainz's,
// and Comic Vine's searches already carry what a log entry needs, so all
// three skip the select -> fetch-details round trip that RAWG and TMDB need.
Item {
  id: root

  property var shell: null

  // ---------------------------------------------------------------- config
  //
  // Lives outside this plugin's directory (which may be a public git repo)
  // so an API key never ends up committed. Shape:
  //   { "vaultPath": "/home/you/Vault", "rawgApiKey": "...", "tmdbApiKey": "...",
  //     "comicVineApiKey": "...", "musicbrainzContact": "you@example.com" }
  readonly property string configPath: Quickshell.env("HOME") + "/.local/state/omarchy/settings/media-journal.json"

  property bool configLoaded: false
  property string configError: ""
  property string vaultPath: ""
  property string rawgApiKey: ""
  property string tmdbApiKey: ""
  property string comicVineApiKey: ""
  // Not a secret — MusicBrainz's usage policy asks every client to identify
  // itself with a way to reach the maintainer (an email or URL) in its
  // User-Agent. Optional; left blank, requests fall back to a generic
  // string that MusicBrainz may rate-limit harder. Deliberately never
  // defaulted to your own email — that would send it to a third party
  // without you having said to.
  property string musicbrainzContact: ""

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root._applyConfig(text())
      // The config holds plaintext API keys; a freshly hand-created file
      // inherits the umask (644 on a common default), which is readable by
      // every local user unless $HOME itself happens to be locked down.
      // Harmless to re-run on every load/reload — a no-op once it's 600.
      configPermsProc.command = ["chmod", "600", root.configPath]
      configPermsProc.running = true
    }
    onLoadFailed: function(error) {
      root.configLoaded = true
      root.vaultPath = ""
      root.rawgApiKey = ""
      root.tmdbApiKey = ""
      root.comicVineApiKey = ""
      root.musicbrainzContact = ""
      root.configError = "No config at " + root.configPath + " — create it with vaultPath + rawgApiKey/tmdbApiKey."
    }
    onFileChanged: reload()
  }

  Process { id: configPermsProc }

  function _applyConfig(text) {
    try {
      var cfg = JSON.parse(text)
      root.vaultPath = String(cfg.vaultPath || "")
      root.rawgApiKey = String(cfg.rawgApiKey || "")
      root.tmdbApiKey = String(cfg.tmdbApiKey || "")
      root.comicVineApiKey = String(cfg.comicVineApiKey || "")
      root.musicbrainzContact = String(cfg.musicbrainzContact || "")
      root.configError = root.vaultPath ? "" : "config.json is missing \"vaultPath\""
    } catch (e) {
      root.vaultPath = ""
      root.rawgApiKey = ""
      root.tmdbApiKey = ""
      root.comicVineApiKey = ""
      root.musicbrainzContact = ""
      root.configError = "config.json is not valid JSON: " + e
    }
    root.configLoaded = true
  }

  // A real client identity, not curl's default one. MusicBrainz's usage
  // policy asks for "Application/Version ( contact )" specifically; Comic
  // Vine doesn't ask but blocks generic/bot-like User-Agents outright, so
  // both curl calls send this. Without a real contact, MusicBrainz still
  // works — just with a worse spot in their rate-limit queue under load.
  function _userAgent() {
    var contact = root.musicbrainzContact.trim() || "no-contact-set"
    return "MediaJournal-Quickshell/0.1 (" + contact + ")"
  }

  function reloadConfig() {
    configFile.reload()
  }

  // ------------------------------------------------------------ game search
  property bool gameSearchBusy: false
  property string gameSearchError: ""
  property string gameSearchQuery: ""
  property var gameResults: []   // [{id, title, year, platforms, backgroundImage, rawgRating}]

  function searchGames(query) {
    if (root.gameSearchBusy) return false   // gameSearchProc is a single shared Process

    query = String(query || "").trim()
    root.gameSearchQuery = query
    root.gameResults = []
    root.gameSearchError = ""

    if (!root.rawgApiKey) {
      root.gameSearchError = "No RAWG API key configured (" + root.configPath + ")"
      return false
    }
    if (!query) return false

    root.gameSearchBusy = true
    gameSearchProc.command = ["curl", "-fsS", "--max-time", "8", Rawg.searchUrl(root.rawgApiKey, query, 10)]
    gameSearchProc.running = true
    return true
  }

  Process {
    id: gameSearchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.gameSearchBusy = false
        var raw = String(text || "").trim()
        if (!raw) {
          root.gameSearchError = "RAWG search failed (network error or bad API key)"
          return
        }
        try {
          root.gameResults = Rawg.parseSearchResults(raw)
          if (root.gameResults.length === 0)
            root.gameSearchError = "No results for \"" + root.gameSearchQuery + "\""
        } catch (e) {
          root.gameSearchError = "Could not parse RAWG response: " + e
        }
      }
    }
  }

  // ---------------------------------------------------------- game details
  //
  // The search endpoint doesn't include developer, so picking a result
  // fetches it before the entry is ready to save.
  property bool gameDetailsBusy: false
  property string gameDetailsError: ""
  property var selectedGame: null   // normalized search hit, merged with details once loaded

  function selectGame(id) {
    if (root.gameDetailsBusy) return false   // gameDetailsProc is a single shared Process

    var hit = null
    for (var i = 0; i < root.gameResults.length; i++) {
      if (root.gameResults[i].id === id) { hit = root.gameResults[i]; break }
    }
    if (!hit) return false

    root.selectedGame = hit
    root.gameDetailsError = ""
    root.gameDetailsBusy = true
    gameDetailsProc.command = ["curl", "-fsS", "--max-time", "8", Rawg.detailsUrl(root.rawgApiKey, id)]
    gameDetailsProc.running = true
    return true
  }

  Process {
    id: gameDetailsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.gameDetailsBusy = false
        var raw = String(text || "").trim()
        if (!raw) {
          root.gameDetailsError = "Could not load game details"
          return
        }
        try {
          var details = Rawg.parseDetails(raw)
          // Only apply if the user hasn't picked something else meanwhile.
          if (root.selectedGame && root.selectedGame.id === details.id)
            root.selectedGame = Object.assign({}, root.selectedGame, details)
        } catch (e) {
          root.gameDetailsError = "Could not parse RAWG details: " + e
        }
      }
    }
  }

  // fields: { rating, review, status, hoursPlayed, platform, dateLogged }
  // rating/status/dateLogged/tags follow the shared frontmatter shape;
  // platform/hoursPlayed/developer are the game-specific fields.
  function writeGameEntry(fields) {
    fields = fields || {}

    if (!root.selectedGame) {
      root.saveError = "No game selected"
      return false
    }

    var game = root.selectedGame
    var entry = {
      type: "game",
      title: game.title,
      creator: game.developer || "",
      year: game.year,
      rating: fields.rating,
      status: fields.status || "completed",
      date_logged: fields.dateLogged || Frontmatter.today(),
      tags: ["media/game"],
      platform: fields.platform || game.platforms || "",
      hours_played: fields.hoursPlayed,
      developer: game.developer || ""
    }

    return root.saveEntry("Games", entry, fields.review, game.id)
  }

  // ------------------------------------------------------------ film search
  property bool filmSearchBusy: false
  property string filmSearchError: ""
  property string filmSearchQuery: ""
  property var filmResults: []   // [{id, title, year, overview, posterPath, tmdbRating}]

  function searchFilms(query) {
    if (root.filmSearchBusy) return false   // filmSearchProc is a single shared Process

    query = String(query || "").trim()
    root.filmSearchQuery = query
    root.filmResults = []
    root.filmSearchError = ""

    if (!root.tmdbApiKey) {
      root.filmSearchError = "No TMDB API key configured (" + root.configPath + ")"
      return false
    }
    if (!query) return false

    root.filmSearchBusy = true
    filmSearchProc.command = ["curl", "-fsS", "--max-time", "8", Tmdb.searchUrl(root.tmdbApiKey, query)]
    filmSearchProc.running = true
    return true
  }

  Process {
    id: filmSearchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.filmSearchBusy = false
        var raw = String(text || "").trim()
        if (!raw) {
          root.filmSearchError = "TMDB search failed (network error or bad API key)"
          return
        }
        try {
          root.filmResults = Tmdb.parseSearchResults(raw)
          if (root.filmResults.length === 0)
            root.filmSearchError = "No results for \"" + root.filmSearchQuery + "\""
        } catch (e) {
          root.filmSearchError = "Could not parse TMDB response: " + e
        }
      }
    }
  }

  // ---------------------------------------------------------- film details
  //
  // The search endpoint doesn't include director/runtime, so picking a
  // result fetches them (via append_to_response=credits) before the entry
  // is ready to save.
  property bool filmDetailsBusy: false
  property string filmDetailsError: ""
  property var selectedFilm: null   // normalized search hit, merged with details once loaded

  function selectFilm(id) {
    if (root.filmDetailsBusy) return false   // filmDetailsProc is a single shared Process

    var hit = null
    for (var i = 0; i < root.filmResults.length; i++) {
      if (root.filmResults[i].id === id) { hit = root.filmResults[i]; break }
    }
    if (!hit) return false

    root.selectedFilm = hit
    root.filmDetailsError = ""
    root.filmDetailsBusy = true
    filmDetailsProc.command = ["curl", "-fsS", "--max-time", "8", Tmdb.detailsUrl(root.tmdbApiKey, id)]
    filmDetailsProc.running = true
    return true
  }

  Process {
    id: filmDetailsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.filmDetailsBusy = false
        var raw = String(text || "").trim()
        if (!raw) {
          root.filmDetailsError = "Could not load film details"
          return
        }
        try {
          var details = Tmdb.parseDetails(raw)
          // Only apply if the user hasn't picked something else meanwhile.
          if (root.selectedFilm && root.selectedFilm.id === details.id)
            root.selectedFilm = Object.assign({}, root.selectedFilm, details)
        } catch (e) {
          root.filmDetailsError = "Could not parse TMDB details: " + e
        }
      }
    }
  }

  // fields: { rating, review, status, rewatch, dateLogged }
  // rating/status/dateLogged/tags follow the shared frontmatter shape;
  // director/runtime/rewatch are the film-specific fields.
  function writeFilmEntry(fields) {
    fields = fields || {}

    if (!root.selectedFilm) {
      root.saveError = "No film selected"
      return false
    }

    var film = root.selectedFilm
    var entry = {
      type: "film",
      title: film.title,
      creator: film.director || "",
      year: film.year,
      rating: fields.rating,
      status: fields.status || "watched",
      date_logged: fields.dateLogged || Frontmatter.today(),
      tags: ["media/film"],
      director: film.director || "",
      runtime: film.runtime,
      rewatch: fields.rewatch === true
    }

    return root.saveEntry("Films", entry, fields.review, film.id)
  }

  // ------------------------------------------------------------ book search
  //
  // Open Library's search endpoint already returns author/year/pages, so
  // there's no details fetch here — selectBook is a synchronous local
  // lookup into the last search results, not a second Process.
  property bool bookSearchBusy: false
  property string bookSearchError: ""
  property string bookSearchQuery: ""
  property var bookResults: []   // [{key, title, author, year, pages, coverId}]

  function searchBooks(query) {
    if (root.bookSearchBusy) return false   // bookSearchProc is a single shared Process

    query = String(query || "").trim()
    root.bookSearchQuery = query
    root.bookResults = []
    root.bookSearchError = ""

    if (!query) return false

    root.bookSearchBusy = true
    bookSearchProc.command = ["curl", "-fsS", "--max-time", "8", OpenLibrary.searchUrl(query, 10)]
    bookSearchProc.running = true
    return true
  }

  Process {
    id: bookSearchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.bookSearchBusy = false
        var raw = String(text || "").trim()
        if (!raw) {
          root.bookSearchError = "Open Library search failed (network error)"
          return
        }
        try {
          root.bookResults = OpenLibrary.parseSearchResults(raw)
          if (root.bookResults.length === 0)
            root.bookSearchError = "No results for \"" + root.bookSearchQuery + "\""
        } catch (e) {
          root.bookSearchError = "Could not parse Open Library response: " + e
        }
      }
    }
  }

  property var selectedBook: null   // normalized search hit; no details fetch needed

  // key: Open Library work key, e.g. "/works/OL21745884W" — not a small
  // integer like RAWG/TMDB ids, so this takes a string.
  function selectBook(key) {
    var hit = null
    for (var i = 0; i < root.bookResults.length; i++) {
      if (root.bookResults[i].key === key) { hit = root.bookResults[i]; break }
    }
    if (!hit) return false

    root.selectedBook = hit
    return true
  }

  // fields: { rating, review, status, format, dateLogged }
  // rating/status/dateLogged/tags follow the shared frontmatter shape;
  // author/pages/format are the book-specific fields.
  function writeBookEntry(fields) {
    fields = fields || {}

    if (!root.selectedBook) {
      root.saveError = "No book selected"
      return false
    }

    var book = root.selectedBook
    var entry = {
      type: "book",
      title: book.title,
      creator: book.author || "",
      year: book.year,
      rating: fields.rating,
      status: fields.status || "read",
      date_logged: fields.dateLogged || Frontmatter.today(),
      tags: ["media/book"],
      author: book.author || "",
      pages: book.pages,
      format: fields.format || ""
    }

    return root.saveEntry("Books", entry, fields.review, book.key)
  }

  // ----------------------------------------------------------- music search
  //
  // MusicBrainz release-group search already returns title/artist/year, so
  // like Open Library there's no details fetch — selectAlbum is a
  // synchronous local lookup. format/label are the physical/digital edition
  // the listener has, which varies by release; same call as book.format,
  // they're user-entered rather than fetched.
  property bool musicSearchBusy: false
  property string musicSearchError: ""
  property string musicSearchQuery: ""
  property var musicResults: []   // [{id, title, artist, year, primaryType}]

  function searchMusic(query) {
    if (root.musicSearchBusy) return false   // musicSearchProc is a single shared Process

    query = String(query || "").trim()
    root.musicSearchQuery = query
    root.musicResults = []
    root.musicSearchError = ""

    if (!query) return false

    root.musicSearchBusy = true
    musicSearchProc.command = [
      "curl", "-fsS", "--max-time", "8",
      "-H", "User-Agent: " + root._userAgent(),
      MusicBrainz.searchUrl(query, 10)
    ]
    musicSearchProc.running = true
    return true
  }

  Process {
    id: musicSearchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.musicSearchBusy = false
        var raw = String(text || "").trim()
        if (!raw) {
          root.musicSearchError = "MusicBrainz search failed (network error)"
          return
        }
        try {
          root.musicResults = MusicBrainz.parseSearchResults(raw)
          if (root.musicResults.length === 0)
            root.musicSearchError = "No results for \"" + root.musicSearchQuery + "\""
        } catch (e) {
          root.musicSearchError = "Could not parse MusicBrainz response: " + e
        }
      }
    }
  }

  property var selectedAlbum: null   // normalized search hit; no details fetch needed

  // id: MusicBrainz release-group MBID (a UUID string).
  function selectAlbum(id) {
    var hit = null
    for (var i = 0; i < root.musicResults.length; i++) {
      if (root.musicResults[i].id === id) { hit = root.musicResults[i]; break }
    }
    if (!hit) return false

    root.selectedAlbum = hit
    return true
  }

  // fields: { rating, review, status, format, label, dateLogged }
  // rating/status/dateLogged/tags follow the shared frontmatter shape;
  // artist/album duplicate creator/title under music-specific names (same
  // convention as developer/director/author); format/label are user-entered.
  function writeMusicEntry(fields) {
    fields = fields || {}

    if (!root.selectedAlbum) {
      root.saveError = "No album selected"
      return false
    }

    var album = root.selectedAlbum
    var entry = {
      type: "music",
      title: album.title,
      creator: album.artist || "",
      year: album.year,
      rating: fields.rating,
      status: fields.status || "listened",
      date_logged: fields.dateLogged || Frontmatter.today(),
      tags: ["media/music"],
      artist: album.artist || "",
      album: album.title,
      format: fields.format || "",
      label: fields.label || ""
    }

    return root.saveEntry("Music", entry, fields.review, album.id)
  }

  // ----------------------------------------------------------- comic search
  //
  // Comic Vine's volume search (a series/run, not a single issue) already
  // returns start_year/publisher/issue count, so — like Open Library and
  // MusicBrainz — there's no details fetch. It does NOT return writer or
  // artist: those are per-issue creator credits Comic Vine only exposes on
  // individual issues, and which legitimately change across a long-running
  // volume, so (same call as book.format / music.format+label) they're
  // user-entered rather than fetched.
  property bool comicSearchBusy: false
  property string comicSearchError: ""
  property string comicSearchQuery: ""
  property var comicResults: []   // [{id, title, year, publisher, issueCount}]

  function searchComics(query) {
    if (root.comicSearchBusy) return false   // comicSearchProc is a single shared Process

    query = String(query || "").trim()
    root.comicSearchQuery = query
    root.comicResults = []
    root.comicSearchError = ""

    if (!root.comicVineApiKey) {
      root.comicSearchError = "No Comic Vine API key configured (" + root.configPath + ")"
      return false
    }
    if (!query) return false

    root.comicSearchBusy = true
    comicSearchProc.command = [
      "curl", "-fsS", "--max-time", "8",
      "-H", "User-Agent: " + root._userAgent(),
      ComicVine.searchUrl(root.comicVineApiKey, query, 10)
    ]
    comicSearchProc.running = true
    return true
  }

  Process {
    id: comicSearchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.comicSearchBusy = false
        var raw = String(text || "").trim()
        if (!raw) {
          root.comicSearchError = "Comic Vine search failed (network error)"
          return
        }
        try {
          root.comicResults = ComicVine.parseSearchResults(raw)
          if (root.comicResults.length === 0)
            root.comicSearchError = "No results for \"" + root.comicSearchQuery + "\""
        } catch (e) {
          // Comic Vine returns HTTP 200 even for a bad key; parseSearchResults
          // throws on its own status_code envelope, which lands here too.
          root.comicSearchError = "Comic Vine error: " + e
        }
      }
    }
  }

  property var selectedComic: null   // normalized search hit; no details fetch needed

  function selectComic(id) {
    var hit = null
    for (var i = 0; i < root.comicResults.length; i++) {
      if (root.comicResults[i].id === id) { hit = root.comicResults[i]; break }
    }
    if (!hit) return false

    root.selectedComic = hit
    return true
  }

  // fields: { rating, review, status, writer, artist, dateLogged }
  // rating/status/dateLogged/tags follow the shared frontmatter shape;
  // writer/artist are user-entered (see comment above); publisher/issues/
  // volume come straight from the search hit.
  function writeComicEntry(fields) {
    fields = fields || {}

    if (!root.selectedComic) {
      root.saveError = "No comic selected"
      return false
    }

    var comic = root.selectedComic
    var entry = {
      type: "comic",
      title: comic.title,
      creator: fields.writer || "",
      year: comic.year,
      rating: fields.rating,
      status: fields.status || "read",
      date_logged: fields.dateLogged || Frontmatter.today(),
      tags: ["media/comic"],
      writer: fields.writer || "",
      artist: fields.artist || "",
      publisher: comic.publisher || "",
      issues: comic.issueCount,
      volume: comic.title
    }

    return root.saveEntry("Comics", entry, fields.review, comic.id)
  }

  // ------------------------------------------------------------- save/write
  //
  // Shared by every media type: one mkdir + one FileView write at a time.
  // Guarded by a single saveBusy flag rather than a per-type one, since a
  // per-type guard wouldn't stop a game save and a film save from stomping
  // on this same pathProc/writerFile pair.
  property bool saveBusy: false
  property string saveError: ""
  property string lastSavedPath: ""
  property var _pendingWrite: null   // {path, markdown} awaiting mkdir -> write

  // entry: frontmatter fields (shared shape + type-specific ones), must
  // include `type` and `title`. folderName: vault subfolder under Media/.
  // uniqueId: the source API's id for this entry — see Frontmatter.slugify's
  // comment for why (disambiguates titles that slugify can't spell in ASCII).
  function saveEntry(folderName, entry, review, uniqueId) {
    if (root.saveBusy) {
      root.saveError = "Already saving — try again in a moment"
      return false
    }
    if (!root.vaultPath) {
      root.saveError = "No vaultPath configured (" + root.configPath + ")"
      return false
    }

    var dir = root.vaultPath + "/Media/" + folderName
    var slug = Frontmatter.slugify(entry.title, uniqueId)
    var markdown = Frontmatter.buildNote(entry, review || "")

    root.saveBusy = true
    root.saveError = ""
    root._pendingWrite = { path: "", markdown: markdown }
    // Re-logging a title must never clobber the earlier note (and its
    // review): the first log gets <slug>.md, later ones <slug>-<date>.md,
    // and same-day repeats <slug>-<date>-2.md, -3, ... The shell picks the
    // first free name and prints it; empty output means mkdir failed.
    // Values go in as positional args, never spliced into the script.
    pathProc.command = ["sh", "-c",
      'mkdir -p "$1" || exit 1\n' +
      'base="$1/$2"\n' +
      'if [ ! -e "$base.md" ]; then printf "%s" "$base.md"; exit 0; fi\n' +
      'p="$base-$3.md"; n=2\n' +
      'while [ -e "$p" ]; do p="$base-$3-$n.md"; n=$((n + 1)); done\n' +
      'printf "%s" "$p"',
      "sh", dir, slug, entry.date_logged || Frontmatter.today()]
    pathProc.running = true
    return true
  }

  Process {
    id: pathProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var path = String(text || "").trim()
        if (!path) {
          root.saveBusy = false
          root.saveError = "Could not create vault folder under " + root.vaultPath + "/Media"
          root._pendingWrite = null
          return
        }
        if (!root._pendingWrite) return
        root._pendingWrite.path = path
        writerFile.path = path
        writerFile.setText(root._pendingWrite.markdown)
      }
    }
  }

  FileView {
    id: writerFile
    printErrors: false
    onSaved: {
      root.saveBusy = false
      root.lastSavedPath = root._pendingWrite ? root._pendingWrite.path : writerFile.path
      root._pendingWrite = null
    }
    onSaveFailed: function(error) {
      root.saveBusy = false
      root.saveError = "Write failed: " + error
      root._pendingWrite = null
    }
  }

  // ------------------------------------------------------------------- IPC
  //
  // Fire-and-forget: these kick work off and return immediately, same as
  // omarchy.media's IpcHandler. An in-process menu should bind to the
  // properties above directly instead of polling status().
  function statusJson() {
    return JSON.stringify({
      configLoaded: root.configLoaded,
      configError: root.configError,
      vaultConfigured: !!root.vaultPath,
      rawgConfigured: !!root.rawgApiKey,
      tmdbConfigured: !!root.tmdbApiKey,
      comicVineConfigured: !!root.comicVineApiKey,
      gameSearchBusy: root.gameSearchBusy,
      gameSearchError: root.gameSearchError,
      gameResultCount: root.gameResults.length,
      gameDetailsBusy: root.gameDetailsBusy,
      selectedGameTitle: root.selectedGame ? root.selectedGame.title : "",
      filmSearchBusy: root.filmSearchBusy,
      filmSearchError: root.filmSearchError,
      filmResultCount: root.filmResults.length,
      filmDetailsBusy: root.filmDetailsBusy,
      selectedFilmTitle: root.selectedFilm ? root.selectedFilm.title : "",
      bookSearchBusy: root.bookSearchBusy,
      bookSearchError: root.bookSearchError,
      bookResultCount: root.bookResults.length,
      selectedBookTitle: root.selectedBook ? root.selectedBook.title : "",
      musicSearchBusy: root.musicSearchBusy,
      musicSearchError: root.musicSearchError,
      musicResultCount: root.musicResults.length,
      selectedAlbumTitle: root.selectedAlbum ? root.selectedAlbum.title : "",
      comicSearchBusy: root.comicSearchBusy,
      comicSearchError: root.comicSearchError,
      comicResultCount: root.comicResults.length,
      selectedComicTitle: root.selectedComic ? root.selectedComic.title : "",
      saveBusy: root.saveBusy,
      saveError: root.saveError,
      lastSavedPath: root.lastSavedPath
    })
  }

  IpcHandler {
    target: "mediajournal"

    function ping(): string {
      return "ok"
    }

    function status(): string {
      return root.statusJson()
    }

    function searchGames(query: string): string {
      return root.searchGames(query) ? "ok" : "unhandled"
    }

    function selectGame(id: string): string {
      var n = parseInt(id, 10)
      if (isNaN(n)) return "unhandled"
      return root.selectGame(n) ? "ok" : "unhandled"
    }

    // fieldsJson: {"rating":4.5,"review":"...","status":"completed","hoursPlayed":12,"platform":"PC"}
    function logGame(fieldsJson: string): string {
      var fields
      try {
        fields = JSON.parse(fieldsJson)
      } catch (e) {
        return "bad-json"
      }
      return root.writeGameEntry(fields) ? "ok" : "unhandled"
    }

    function searchFilms(query: string): string {
      return root.searchFilms(query) ? "ok" : "unhandled"
    }

    function selectFilm(id: string): string {
      var n = parseInt(id, 10)
      if (isNaN(n)) return "unhandled"
      return root.selectFilm(n) ? "ok" : "unhandled"
    }

    // fieldsJson: {"rating":4,"review":"...","status":"watched","rewatch":false}
    function logFilm(fieldsJson: string): string {
      var fields
      try {
        fields = JSON.parse(fieldsJson)
      } catch (e) {
        return "bad-json"
      }
      return root.writeFilmEntry(fields) ? "ok" : "unhandled"
    }

    function searchBooks(query: string): string {
      return root.searchBooks(query) ? "ok" : "unhandled"
    }

    // key is an Open Library work key, e.g. "/works/OL21745884W".
    function selectBook(key: string): string {
      return root.selectBook(key) ? "ok" : "unhandled"
    }

    // fieldsJson: {"rating":4,"review":"...","status":"read","format":"paperback"}
    function logBook(fieldsJson: string): string {
      var fields
      try {
        fields = JSON.parse(fieldsJson)
      } catch (e) {
        return "bad-json"
      }
      return root.writeBookEntry(fields) ? "ok" : "unhandled"
    }

    function searchMusic(query: string): string {
      return root.searchMusic(query) ? "ok" : "unhandled"
    }

    // id is a MusicBrainz release-group MBID (a UUID string).
    function selectAlbum(id: string): string {
      return root.selectAlbum(id) ? "ok" : "unhandled"
    }

    // fieldsJson: {"rating":4,"review":"...","status":"listened","format":"vinyl","label":"..."}
    function logMusic(fieldsJson: string): string {
      var fields
      try {
        fields = JSON.parse(fieldsJson)
      } catch (e) {
        return "bad-json"
      }
      return root.writeMusicEntry(fields) ? "ok" : "unhandled"
    }

    function searchComics(query: string): string {
      return root.searchComics(query) ? "ok" : "unhandled"
    }

    function selectComic(id: string): string {
      var n = parseInt(id, 10)
      if (isNaN(n)) return "unhandled"
      return root.selectComic(n) ? "ok" : "unhandled"
    }

    // fieldsJson: {"rating":4,"review":"...","status":"read","writer":"...","artist":"..."}
    function logComic(fieldsJson: string): string {
      var fields
      try {
        fields = JSON.parse(fieldsJson)
      } catch (e) {
        return "bad-json"
      }
      return root.writeComicEntry(fields) ? "ok" : "unhandled"
    }
  }
}
