# Media Journal

An [Omarchy](https://omarchy.org) Quickshell plugin for logging what you
watch, read, play, and listen to (films, TV shows, books, games, comics and
music) straight into an Obsidian vault as markdown notes with ratings and
reviews. Think Letterboxd + Goodreads + a TV, game, music and comic log,
unified into one personal media diary that lives in plain files you already
own.

## Features

- **Real catalog search** for each media type, so every entry starts with
  real metadata (year, developer, director, creator, author, artist,
  publisher, ...) and cover art. You add your rating, review and status.
- **Cover art** in search results, in the entry form and in your recent
  entries, and saved to each note.
- **Recent entries:** with the search box empty, the menu lists your latest
  entries of every type, newest first. Click one to read or edit it.
- **Logged before:** pick a search result you've logged already and your past
  entries for it appear above the form, with the start of each review.
- **Edit in place:** change the rating, status or review of any past entry,
  or add to the review. Anything else in the note, including edits you made
  in Obsidian, is kept.
- **Re-logs never overwrite:** rewatching a film or replaying a game saves a
  new dated note, so each time keeps its own rating and review. TV entries
  can be logged per season.
- **Dataview dashboard** for Obsidian: this month, best of the year, in
  progress, per-type tables and all-time stats.

| Type   | Source                                                          | API key |
|--------|------------------------------------------------------------------|:-------:|
| Game   | [RAWG](https://rawg.io/apidocs)                                   | yes     |
| Film   | [TMDB](https://www.themoviedb.org/settings/api)                   | yes     |
| TV     | [TMDB](https://www.themoviedb.org/settings/api) (same key)        | yes     |
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
  media types that use them (games, films and TV, comics). Open Library
  and MusicBrainz need no key at all. All three keys are free:
  [RAWG](https://rawg.io/apidocs), [TMDB](https://www.themoviedb.org/settings/api),
  [Comic Vine](https://comicvine.gamespot.com/api/).
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
  TV/<slug>.md
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
| `type` | `game`, `film`, `tv`, `book`, `music` or `comic` |
| `title`, `creator`, `year` | From the catalog. `creator` is the developer, director, show creator, author, artist or writer. `year` is the release (or first air) year |
| `rating` | 0–5 in half steps. `0` means unrated |
| `status` | See below |
| `date_logged` | `YYYY-MM-DD`, the day you logged it |
| `tags` | `media/<type>` |
| `cover` | Cover image URL from the catalog |
| `source_id` | The catalog's id, e.g. `rawg:1014273`. Used to match search results to your past entries |

Each type adds its own fields, and each has its own status values:

| Type | Extra fields | Status values |
|------|--------------|---------------|
| Game | `platform`, `hours_played`, `developer` | `playing`, `completed`, `dropped`, `backlog` |
| Film | `director`, `runtime`, `rewatch` | `watched`, `rewatching`, `dropped` |
| TV | `network`, `seasons` (total), `season` (the one you watched; omitted for the whole show) | `watching`, `completed`, `rewatching`, `dropped`, `backlog` |
| Book | `author`, `pages`, `format` | `reading`, `read`, `dnf`, `backlog` |
| Music | `artist`, `album`, `format`, `label` | `listened`, `favorite` |
| Comic | `writer`, `artist`, `publisher`, `issues`, `volume` | `reading`, `read`, `dropped`, `backlog` |

Empty fields are left out of the frontmatter. Editing an entry from the menu
rewrites only rating, status, the review and the type's own fields shown in
the form. Any other lines, including ones you added in Obsidian, are kept.
Notes from before `cover` and `source_id` existed get them filled in the
next time you edit them: from the search result you opened them under, or
from an exact title match in the catalog. For comics, `writer` and
`artist` are typed in by you, because Comic Vine only lists credits per
issue, not per volume.

## Dashboard

Copy `Media Journal.md` from this repo into your vault's `Media/` folder for a
[Dataview](https://blacksmithgu.github.io/obsidian-dataview/) dashboard:
this month, best of the year (by date logged), in progress, a table per
type, and all-time stats (average ratings skip unrated entries).
Requires the Dataview community plugin installed and enabled in Obsidian.
Open it in Reading view or Live Preview. Source mode shows the raw queries.

## Scripting (IPC)

Everything the menu does is also available over IPC, e.g. from a keybinding
or a script:

```bash
omarchy-shell mediajournal status                  # config + busy/error state, JSON
omarchy-shell mediajournal searchFilms "Heat"      # async; results land in the service
omarchy-shell mediajournal selectFilm 949
omarchy-shell mediajournal logFilm '{"rating":4.5,"status":"watched","review":"..."}'
omarchy-shell mediajournal loadEntries             # then:
omarchy-shell mediajournal entries                 # every logged entry, JSON
omarchy-shell mediajournal editEntry "<path>" '{"rating":5,"status":"watched","review":"..."}'
```

Each type has `searchX` / `selectX` / `logX`: Games, Films, Tv, Books,
Album (`searchMusic`/`selectAlbum`/`logMusic`) and Comics. `logX` takes the
same fields as the form (`rating`, `status`, `review`, plus the type's own,
such as `hoursPlayed`, `platform`, `season`, `format`). `editEntry` only
accepts notes under `<vaultPath>/Media/`.

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
- `lib/Frontmatter.js` — builds notes, and parses and updates them for
  past entries and editing. Updates only touch the keys they're given.

Adding a media type means:

1. A normalizer in `lib/<Api>.js` that returns `{id, title, year, coverUrl, ...}`.
2. In `Service.qml`: a search `Process` (plus a details one if the search
   endpoint is thin), a `writeXEntry()` that builds the frontmatter and calls
   `saveEntry()`, and entries in `_folders`, `sourceIdFor()`,
   `_editChanges()` and the cover-lookup helpers.
3. In `MediaMenu.qml`: the type in `mediaTypes`, a branch in each per-type
   dispatch function, its status values, and any type-specific form fields.
4. A table in `Media Journal.md`.

To hack on it, install your local clone as a git checkout, not a symlink:
`omarchy plugin add ~/path/to/media-journal --enable`. The installed copy only
sees committed code. After each commit, run `omarchy plugin update
aimabe.mediajournal` and then `omarchy-restart-shell`.

## License

MIT — see `LICENSE`.
