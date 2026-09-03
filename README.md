# Media Journal

An [Omarchy](https://omarchy.org) Quickshell plugin for logging what you
watch, read, play, and listen to — films, books, games, comics, music —
straight into an Obsidian vault as markdown notes with ratings and reviews.
Letterboxd + Goodreads + a game/music/comic log, unified into one personal
media diary that lives in plain files you already own.

Search happens against the real catalog for each media type, so a logged
entry starts with real metadata (year, developer, director, author, artist,
publisher, ...) — you just add your rating, review, and status.

| Type   | Source                                                          | API key |
|--------|------------------------------------------------------------------|:-------:|
| Game   | [RAWG](https://rawg.io/apidocs)                                   | yes     |
| Film   | [TMDB](https://www.themoviedb.org/settings/api)                   | yes     |
| Book   | [Open Library](https://openlibrary.org/dev/docs/api/search)       | no      |
| Music  | [MusicBrainz](https://musicbrainz.org/doc/MusicBrainz_API)         | no      |
| Comic  | [Comic Vine](https://comicvine.gamespot.com/api/)                  | yes     |

## Install

```bash
omarchy plugin add https://github.com/AimAbe/media-journal.git --enable --yes
```

Or clone by hand into `~/.config/omarchy/plugins/aimen.mediajournal/`
and run `omarchy-shell shell rescanPlugins`. See the
[plugin docs](https://github.com/basecamp/omarchy/blob/master/shell/README.md)
for the general install/enable flow.

A boxed-pencil icon appears in the bar (default: right section — move it with
`omarchy bar move aimen.mediajournal --section center`). Click it to
open the menu, or bind a key:

```
# ~/.config/hypr/bindings.conf
bindd = SUPER, M, Log media, exec, omarchy-shell shell toggle aimen.mediajournal '{}'
```

## Configure

Create `~/.local/state/omarchy/settings/media-journal.json` — deliberately
outside this plugin's own directory, so an API key never ends up committed
if you fork or update this repo:

```json
{
  "vaultPath": "/home/you/path/to/your/Vault",
  "rawgApiKey": "your RAWG key",
  "tmdbApiKey": "your TMDB key",
  "comicVineApiKey": "your Comic Vine key",
  "musicbrainzContact": "you@example.com"
}
```

- `vaultPath` is required for anything else to work.
- `rawgApiKey` / `tmdbApiKey` / `comicVineApiKey` are only needed for the
  media types that use them (games/films/comics) — Open Library and
  MusicBrainz need no key at all.
- `musicbrainzContact` is optional but recommended: MusicBrainz's usage
  policy asks every client to identify itself with a way to reach the
  maintainer. Left blank, requests still work, just with a worse spot in
  MusicBrainz's rate-limit queue under load.

The plugin sets this file to `600` permissions on every load (it holds
plaintext API keys) — if you ever hand-edit it, that's expected, not a bug.

## What gets written

```
<vaultPath>/Media/
  Games/<slug>.md
  Films/<slug>.md
  Books/<slug>.md
  Music/<slug>.md
  Comics/<slug>.md
```

Each note is YAML frontmatter (shared fields — `type`, `title`, `creator`,
`year`, `rating`, `status`, `date_logged`, `tags` — plus type-specific ones)
followed by your review as the note body. See `plan.md` for the exact field
list per type.

## Dashboard

Copy `Media Journal.md` from this repo into your vault root for a
[Dataview](https://blacksmithgu.github.io/obsidian-dataview/) dashboard —
this month, best of the year, in-progress, per-type tables, and an all-time
stats summary. Requires the Dataview community plugin installed and
enabled in Obsidian.

## Architecture, for anyone extending this

- `Service.qml` — the `service`-kind plugin: config, per-type search
  (`lib/<Api>.js` normalizes each API's response), and a shared
  `saveEntry()` that every `writeXEntry()` hands off to for the actual
  frontmatter build + file write.
- `MediaMenu.qml` — the `menu`-kind summoned surface. Binds directly to
  `Service.qml`'s reactive properties (the shell auto-wires
  `menu.service = service` since they share one manifest id) rather than
  going through IPC — IPC exists on `Service.qml` for external callers
  (keybindings, scripting) instead.
- `BarWidget.qml` — a `qs.Ui.BarIconButton` that toggles the menu via
  `omarchy-shell shell toggle`, matching the convention every first-party
  icon-only widget uses.

Adding a media type means one `lib/<Api>.js` normalizer, a search (+
details, if the search endpoint doesn't carry enough) `Process` in
`Service.qml`, and a `writeXEntry()` that builds the frontmatter object and
calls `saveEntry()`.

## License

MIT — see `LICENSE`.
