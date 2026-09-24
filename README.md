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

## Requirements

- Omarchy 4 (Quattro) / `omarchy-shell` (Quickshell). This is a shell plugin,
  not a standalone app. Tested on Omarchy 4.0.4.
- `curl` — every search shells out to it directly; almost certainly already
  on your system.
- [Obsidian](https://obsidian.md) with the
  [Dataview](https://blacksmithgu.github.io/obsidian-dataview/) community
  plugin, only if you want the dashboard (`Media Journal.md`) to render —
  logging entries works without it.

## Install

```bash
omarchy plugin add https://github.com/AimAbe/media-journal.git --enable --yes
```

Or clone by hand into `~/.config/omarchy/plugins/aimabe.mediajournal/`, then
run `omarchy plugin enable aimabe.mediajournal`. It has to be a real folder:
Omarchy rejects plugin folders that are symlinks. See the
[plugin docs](https://github.com/omacom/omarchy/blob/master/shell/README.md)
for the general install/enable flow.

A boxed-pencil icon appears in the bar (default: right section — move it with
`omarchy bar move aimabe.mediajournal --section center`). Click it to
open the menu, or bind a key:

```
# ~/.config/hypr/bindings.conf
bindd = SUPER, M, Log media, exec, omarchy-shell shell toggle aimabe.mediajournal '{}'
```

## Update

```bash
omarchy plugin update aimabe.mediajournal
omarchy-restart-shell
```

A full shell restart is needed because the plugin's `lib/*.js` files aren't
hot-reloaded.

## Uninstall

```bash
omarchy plugin remove aimabe.mediajournal --yes
```

This removes the plugin's entry from `~/.config/omarchy/shell.json` and
deletes `~/.config/omarchy/plugins/aimabe.mediajournal/`. It doesn't touch
anything it already wrote — your vault's `Media/` notes and
`~/.local/state/omarchy/settings/media-journal.json` (your API keys) are
left alone; delete those yourself if you want them gone too.

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

Each note is YAML frontmatter followed by your review as the note body. Files
are named after a slug of the title. Logging the same title again never
overwrites the earlier note: the re-log is saved as `<slug>-<date>.md` (and
`<slug>-<date>-2.md`, ... for more than one on the same day), so every
rewatch or replay keeps its own rating and review.

Every note has these shared fields:

| Field | Meaning |
|-------|---------|
| `type` | `game`, `film`, `book`, `music` or `comic` |
| `title`, `creator`, `year` | From the catalog. `creator` is the developer, director, author, artist or writer. `year` is the release year |
| `rating` | 0–5 in half steps. `0` means unrated |
| `status` | See below |
| `date_logged` | `YYYY-MM-DD`, the day you logged it |
| `tags` | `media/<type>` |

Each type adds its own fields, and each has its own status values:

| Type | Extra fields | Status values |
|------|--------------|---------------|
| Game | `platform`, `hours_played`, `developer` | `playing`, `completed`, `dropped`, `backlog` |
| Film | `director`, `runtime`, `rewatch` | `watched`, `rewatching`, `dropped` |
| Book | `author`, `pages`, `format` | `reading`, `read`, `dnf`, `backlog` |
| Music | `artist`, `album`, `format`, `label` | `listened`, `favorite` |
| Comic | `writer`, `artist`, `publisher`, `issues`, `volume` | `reading`, `read`, `dropped`, `backlog` |

Empty fields are left out of the frontmatter. For comics, `writer` and
`artist` are typed in by you, because Comic Vine only lists credits per
issue, not per volume.

## Dashboard

Copy `Media Journal.md` from this repo into your vault's `Media/` folder for a
[Dataview](https://blacksmithgu.github.io/obsidian-dataview/) dashboard —
this month, best of the year (by date logged), in-progress, per-type tables,
and an all-time stats summary (average ratings skip unrated entries).
Requires the Dataview community plugin installed and enabled in Obsidian.
Open it in Reading view or Live Preview. Source mode shows the raw queries.

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

To hack on it, install your local clone as a git checkout, not a symlink:
`omarchy plugin add ~/path/to/media-journal --enable`. The installed copy only
sees committed code. After each commit, run `omarchy plugin update
aimabe.mediajournal` and then `omarchy-restart-shell`.

## License

MIT — see `LICENSE`.
