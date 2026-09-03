# Omarchy Media Journal Plugin — Build Plan

## Goal
An Omarchy Quickshell plugin that logs media consumption (films, books,
video games, comics, music) with ratings + reviews, writing entries as
markdown notes into an Obsidian vault. Think Letterboxd + Goodreads +
RAWG, unified into one personal media diary.

## Plugin Identity
- id: `<yourname>.mediajournal`   (username prefix; `omarchy.` is reserved)
- kinds: `service`, `menu`, `bar-widget`
- location: `~/.config/omarchy/plugins/<yourname>.mediajournal/`

---

## Phase 0 — Recon (do this FIRST)
- [x] Run `omarchy plugin list --json` to find the built-in media plugin id.
      → `omarchy.media` (service + bar-widget, MPRIS now-playing — not a
      media-cataloging plugin, but the right IPC/service reference).
- [x] Run `omarchy plugin clone omarchy.<media-id> --edit` to get a working
      service + bar-widget reference. → cloned to `aimen.media`, copied into
      `reference/omarchy.media/` in this repo (gitignore it before publishing).
- [x] Read `shell/README.md` (manifest schema, IPC contract, shell.json shape).
- [x] Read `shell/plugins/README.md` (first-party plugin list + entry points).
- [x] Note: plugins run UNSANDBOXED in the long-lived shell — review all code,
      store API keys carefully. → API keys live in
      `~/.local/state/omarchy/settings/media-journal.json`, outside this
      repo, never committed.

## Phase 1 — Scaffold
- [x] Create plugin directory + `manifest.json` (schemaVersion 1).
- [x] Add entryPoints: service / menu / bar-widget QML files.
- [x] `omarchy plugin validate ./` until it passes.
- [x] `omarchy plugin add` (or symlink) + enable; confirm it loads.
      → symlinked `~/.config/omarchy/plugins/aimen.mediajournal` to this repo.
      **Gotcha:** a symlinked plugin dir breaks the shell's inotify-based
      auto-reload (it doesn't traverse symlinks) — `omarchy-shell shell
      rescanPlugins` after every edit, `omarchy-restart-shell` after editing
      any `lib/*.js` file (plain JS imports don't hot-reload even on rescan).

### manifest.json (starting point)
{
  "schemaVersion": 1,
  "id": "<yourname>.mediajournal",
  "name": "Media Journal",
  "version": "0.1.0",
  "kinds": ["service", "menu", "bar-widget"],
  "entryPoints": {
    "service": "MediaService.qml",
    "menu": "MediaMenu.qml",
    "bar-widget": "MediaWidget.qml"
  },
  "barWidget": {
    "name": "Media Journal",
    "category": "productivity",
    "defaultSection": "right",
    "allowMultiple": false
  }
}

## Phase 2 — Data Model
Shared frontmatter for every entry:
- type (film|book|game|comic|music), title, creator, year,
  rating (0–5, half-steps), status, date_logged, tags[], review

Type-specific fields:
- film:  director, runtime, rewatch
- book:  author, pages, format
- game:  platform, hours_played, developer
- comic: writer, artist, issues/volume, publisher
- music: artist, album, format, label

Vault layout:
  Vault/Media/{Films,Books,Games,Comics,Music}/<slug>.md
  Vault/Media Journal.md   (Dataview dashboard)

## Phase 3 — Service Layer (Service.qml)
- [x] Config: vault path, API keys (read from a config file, NOT hardcoded).
- [x] Per-media search functions (see API table below).
- [x] Markdown/frontmatter builder (shared + type-specific fields).
- [x] File writer: slugify title, write to correct folder.
- [x] Expose IPC methods for the menu to call (match cloned plugin's pattern).
      → `IpcHandler { target: "mediajournal" }`; the menu itself talks to
      the service directly in-process (`service` property auto-wired by the
      shell since menu + service share one manifest id) rather than via IPC.

### API Reference
| Media  | API                         | Key? | Status |
|--------|-----------------------------|------|--------|
| film   | TMDB                        | yes  | done — search + credits (director/runtime) |
| book   | Open Library / Google Books | no   | done — search alone has author/year/pages |
| game   | RAWG.io or IGDB             | yes  | done — search + details (developer) |
| comic  | Comic Vine / Metron         | yes  | done — volume search (writer/artist are user-entered; Comic Vine doesn't expose them at volume level) |
| music  | MusicBrainz / Last.fm       | no   | done — release-group search; needs a descriptive User-Agent (see musicbrainzContact in config) |

(MusicBrainz + Open Library need no key — good for first prototype; both
also skip the search→details round trip RAWG/TMDB need, since their search
responses already carry what a log entry needs.)

## Phase 4 — Menu UI (MediaMenu.qml)
- [x] Media-type selector.
- [x] Search input -> calls service search.
- [x] Result picker.
- [x] Rating input (stars / 0–5). → built as a 0.5-step PanelSlider instead
      of a star-click grid; same precision, much less code.
- [x] Review text field.
- [x] Save -> service writes markdown.

## Phase 5 — Bar Widget (BarWidget.qml)
- [x] Button that summons the menu (📖, bar right section). Toggling
      confirmed working by hand.
- [ ] Indicator showing last logged item — not built; optional per plan.

## Phase 6 — Obsidian Dashboard
- [x] Dataview: "this month" table across all Media.
- [x] Dataview: "best of year" (rating >= 4.5, dynamic current year).
- [x] Per-type views, plus an all-time stats table (count + avg rating by
      type) not originally in the plan.
      → written to `<vaultPath>/Media Journal.md`. **Not yet verified
      rendering**: the vault has no `.obsidian/` folder yet, meaning it's
      never been opened in Obsidian, so the Dataview community plugin isn't
      installed. Open the vault, install + enable Dataview, confirm the
      dashboard actually renders.

## Phase 7 — Polish & Share
- [x] Handle API failures / no results gracefully. → 36 distinct error
      paths across config/search/save (missing key, no results, network
      failure, bad JSON, no vault, mkdir/write failure, busy-guards).
- [x] `omarchy plugin validate` clean.
- [x] Public git repo. → git-initialized, first commit made, README +
      LICENSE (MIT) written. **Not yet pushed anywhere** — no GitHub remote
      exists yet, that's the one open step.
- [ ] List at omarchyplugins.com. → needs the GitHub remote above first;
      haven't looked at their submission process yet.

---

## Open Questions — resolved
1. Service singleton + IPC: `Item { IpcHandler { target: "..." } }`, exactly
   the cloned plugin's shape. Third-party services get instantiated the
   same way first-party ones do, once enabled in `shell.json`.
2. A `menu` surface is a `PanelWindow` (`WlrLayershell.keyboardFocus:
   Exclusive`) with `function open(payloadJson)` / `function close()` —
   the shell's panel Loader calls these on summon/hide. Modeled
   `MediaMenu.qml` on `omarchy.emojis`' PanelWindow/scrim/card shell, built
   from `qs.Ui`'s real form controls instead of hand-rolled key catching.
3. The bar-widget doesn't call the service directly — it shells out to
   `omarchy-shell shell toggle aimen.mediajournal '{}'` via `bar.run(...)`,
   matching every first-party bar-widget's own convention (e.g.
   `omarchy.menu`'s `BarWidget.qml`) rather than reaching into
   `bar.shell.toggle(...)` in-process.

## Dataview snippets (as shipped — see Media Journal.md in the vault)
This month (rewritten — `date(this.month)` isn't valid DQL):
    TABLE type, creator, rating, date_logged AS "Logged"
    FROM "Media"
    WHERE dateformat(date_logged, "yyyy-MM") = dateformat(date(today), "yyyy-MM")
    SORT date_logged DESC

Best of year (rewritten — dynamic year instead of a hardcoded one):
    TABLE title, type, creator, rating
    FROM "Media"
    WHERE year = date(today).year AND rating >= 4.5
    SORT rating DESC
