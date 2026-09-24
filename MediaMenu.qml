import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Media Journal menu — the summoned surface for logging an entry: pick a
// media type, search, select a result, fill in rating/review/type-specific
// fields, save. Modeled on omarchy.emojis's PanelWindow/scrim/card shell,
// but built from qs.Ui's form controls (TextField/Dropdown/PanelSlider/
// ToggleSwitch) instead of hand-rolled key catching, since this is a form
// the user types into rather than a keyboard-navigated grid.
//
// With an empty search box it lists your recent entries of the current
// type; picking one (or a past entry shown under a selected search result)
// opens it for editing in place instead of logging a new one.
//
// `service` is not wired up here — the shell's generic panel loader sets
// it to serviceFor(<this plugin's id>) once loaded (shell.qml: "if
// ('service' in item) item.service = shell.serviceFor(...)"), since this
// menu and Service.qml share one manifest id. Every search/select/write
// call below just forwards to that instance; all the real logic (API
// calls, frontmatter, file writes) lives there.
Item {
  id: root

  property var shell: null
  property var service: null

  property bool opened: false

  function open(payloadJson) {
    root.opened = true
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") || {} } catch (e) { payload = {} }
    if (payload.mediaType && root._isKnownType(payload.mediaType))
      root.mediaType = payload.mediaType

    searchField.text = ""
    root.hasActiveSelection = false
    root.editingEntry = null
    root.savedConfirmation = ""
    if (root.service) root.service.loadEntries(root.mediaType)
    Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide("aimabe.mediajournal")
  }

  // ------------------------------------------------------------ media type
  readonly property var mediaTypes: [
    { value: "game", label: "Game" },
    { value: "film", label: "Film" },
    { value: "book", label: "Book" },
    { value: "music", label: "Music" },
    { value: "comic", label: "Comic" }
  ]
  property string mediaType: "game"

  function _isKnownType(t) {
    for (var i = 0; i < root.mediaTypes.length; i++) if (root.mediaTypes[i].value === t) return true
    return false
  }

  function changeMediaType(next) {
    root.mediaType = next
    searchField.text = ""
    root.hasActiveSelection = false
    root.editingEntry = null
    root.savedConfirmation = ""
    if (root.service) root.service.loadEntries(next)
  }

  // ---------------------------------------------------- per-type dispatch
  //
  // One switch per operation instead of duplicating the whole panel five
  // times. Keeps this file the same shape regardless of how many media
  // types Service.qml grows.
  function results() {
    if (!root.service) return []
    if (root.mediaType === "game") return root.service.gameResults
    if (root.mediaType === "film") return root.service.filmResults
    if (root.mediaType === "book") return root.service.bookResults
    if (root.mediaType === "music") return root.service.musicResults
    if (root.mediaType === "comic") return root.service.comicResults
    return []
  }

  function selected() {
    if (!root.service) return null
    if (root.mediaType === "game") return root.service.selectedGame
    if (root.mediaType === "film") return root.service.selectedFilm
    if (root.mediaType === "book") return root.service.selectedBook
    if (root.mediaType === "music") return root.service.selectedAlbum
    if (root.mediaType === "comic") return root.service.selectedComic
    return null
  }

  function searchBusy() {
    if (!root.service) return false
    if (root.mediaType === "game") return root.service.gameSearchBusy
    if (root.mediaType === "film") return root.service.filmSearchBusy
    if (root.mediaType === "book") return root.service.bookSearchBusy
    if (root.mediaType === "music") return root.service.musicSearchBusy
    if (root.mediaType === "comic") return root.service.comicSearchBusy
    return false
  }

  function searchError() {
    if (!root.service) return ""
    if (root.mediaType === "game") return root.service.gameSearchError
    if (root.mediaType === "film") return root.service.filmSearchError
    if (root.mediaType === "book") return root.service.bookSearchError
    if (root.mediaType === "music") return root.service.musicSearchError
    if (root.mediaType === "comic") return root.service.comicSearchError
    return ""
  }

  // Result rows share {title, year} but differ on the secondary detail —
  // this is the one thing worth normalizing here rather than in Service.qml,
  // since it's purely a display choice.
  function resultSubtitle(hit) {
    if (!hit) return ""
    var year = hit.year ? String(hit.year) : "—"
    if (root.mediaType === "game") return year + (hit.platforms ? " · " + hit.platforms : "")
    if (root.mediaType === "film") return year
    if (root.mediaType === "book") return year + (hit.author ? " · " + hit.author : "")
    if (root.mediaType === "music") return year + (hit.artist ? " · " + hit.artist : "")
    if (root.mediaType === "comic") return year + (hit.publisher ? " · " + hit.publisher : "")
    return year
  }

  // Covers come in different shapes: game art is landscape, album art is
  // square, posters and book/comic covers are portrait.
  function coverWidth(height) {
    if (root.mediaType === "game") return Math.round(height * 1.5)
    if (root.mediaType === "music") return height
    return Math.round(height * 0.67)
  }

  // ------------------------------------------------------- past entries
  property bool showingRecent: searchField.text.trim() === ""

  function recentEntries() {
    if (!root.service || root.service.entriesType !== root.mediaType) return []
    return root.service.entries.slice(0, 25)
  }

  function pastEntries() {
    if (!root.service || root.editingEntry) return []
    return root.service.pastEntriesFor(root.mediaType, root.selected())
  }

  function entrySubtitle(entry) {
    var f = entry.fields || {}
    var parts = []
    if (Number(f.rating) > 0) parts.push("★ " + Number(f.rating).toFixed(1))
    if (f.status) parts.push(String(f.status))
    if (f.date_logged) parts.push(String(f.date_logged))
    return parts.join(" · ")
  }

  // One list serves both the recent entries and the search results.
  function listModel() {
    return root.showingRecent ? root.recentEntries() : root.results()
  }

  function rowTitle(item) {
    return item ? String(item.title || "") : ""
  }

  function rowSubtitle(item) {
    if (!item) return ""
    if (root.showingRecent) return root.entrySubtitle(item)
    var sub = root.resultSubtitle(item)
    var logged = root.service ? root.service.pastEntriesFor(root.mediaType, item).length : 0
    if (logged) sub += " · logged" + (logged > 1 ? " ×" + logged : "")
    return sub
  }

  function rowCover(item) {
    if (!item) return ""
    if (!root.showingRecent) return String(item.coverUrl || "")
    var found = root.lookedUp(item)
    return String((item.fields && item.fields.cover) || (found ? found.coverUrl : ""))
  }

  function activateRow(item) {
    if (root.showingRecent) root.openEntry(item, false)
    else root.selectResult(item)
  }

  // null while logging something new; the entry being edited otherwise.
  property var editingEntry: null
  // Opened from a selected search result's "Logged before" list: Back
  // returns to that result's new-log form rather than to search.
  property bool editReturnsToForm: false

  function openEntry(entry, fromForm) {
    if (!entry) return
    root.editingEntry = entry
    root.editReturnsToForm = fromForm === true
    root.hasActiveSelection = true
    root.savedConfirmation = ""
    root.prefillFromEntry(entry)
    if (root.service) root.service.lookupCover(entry)
  }

  // A note without a cover borrows the one the service looked up for it.
  function lookedUp(entry) {
    var l = root.service ? root.service.coverLookup : null
    return l && entry && l.path === entry.path ? l : null
  }

  function prefillFromEntry(entry) {
    var f = entry.fields || {}
    root.ratingValue = Math.round((Number(f.rating) || 0) * 2) / 2
    root.statusValue = f.status ? String(f.status) : root.defaultStatus()
    root.rewatchValue = f.rewatch === true
    reviewField.text = entry.review || ""
    hoursPlayedField.field.value = Number(f.hours_played) || 0
    platformField.text = f.platform ? String(f.platform) : ""
    formatField.text = f.format ? String(f.format) : ""
    labelField.text = f.label ? String(f.label) : ""
    writerField.text = f.writer ? String(f.writer) : ""
    artistField.text = f.artist ? String(f.artist) : ""
  }

  // What the form header shows, for either mode.
  function headerInfo() {
    if (root.editingEntry) {
      var f = root.editingEntry.fields || {}
      var found = root.lookedUp(root.editingEntry)
      return { title: root.editingEntry.title, year: f.year || "", creator: f.creator || "", cover: f.cover || (found ? found.coverUrl : "") }
    }
    var s = root.selected()
    if (!s) return { title: "", year: "", creator: "", cover: "" }
    return {
      title: s.title,
      year: s.year || "",
      creator: s.developer || s.director || s.author || s.artist || s.publisher || "",
      cover: s.coverUrl || ""
    }
  }

  function runSearch(query) {
    if (!root.service) return
    if (root.mediaType === "game") root.service.searchGames(query)
    else if (root.mediaType === "film") root.service.searchFilms(query)
    else if (root.mediaType === "book") root.service.searchBooks(query)
    else if (root.mediaType === "music") root.service.searchMusic(query)
    else if (root.mediaType === "comic") root.service.searchComics(query)
  }

  function selectResult(hit) {
    if (!root.service || !hit) return
    var ok = false
    if (root.mediaType === "game") ok = root.service.selectGame(hit.id)
    else if (root.mediaType === "film") ok = root.service.selectFilm(hit.id)
    else if (root.mediaType === "book") ok = root.service.selectBook(hit.key)
    else if (root.mediaType === "music") ok = root.service.selectAlbum(hit.id)
    else if (root.mediaType === "comic") ok = root.service.selectComic(hit.id)
    if (ok) {
      root.hasActiveSelection = true
      root.resetFormFields()
    }
  }

  function backToSearch() {
    root.savedConfirmation = ""
    if (root.editingEntry && root.editReturnsToForm) {
      root.editingEntry = null
      root.resetFormFields()
      return
    }
    root.editingEntry = null
    root.hasActiveSelection = false
  }

  function saveSelected(fields) {
    if (!root.service) return false
    if (root.mediaType === "game") return root.service.writeGameEntry(fields)
    if (root.mediaType === "film") return root.service.writeFilmEntry(fields)
    if (root.mediaType === "book") return root.service.writeBookEntry(fields)
    if (root.mediaType === "music") return root.service.writeMusicEntry(fields)
    if (root.mediaType === "comic") return root.service.writeComicEntry(fields)
    return false
  }

  function defaultStatus() {
    if (root.mediaType === "game") return "playing"
    if (root.mediaType === "film") return "watched"
    if (root.mediaType === "book") return "reading"
    if (root.mediaType === "music") return "listened"
    if (root.mediaType === "comic") return "reading"
    return ""
  }

  function statusOptions() {
    if (root.mediaType === "game") return ["playing", "completed", "dropped", "backlog"]
    if (root.mediaType === "film") return ["watched", "rewatching", "dropped"]
    if (root.mediaType === "book") return ["reading", "read", "dnf", "backlog"]
    if (root.mediaType === "music") return ["listened", "favorite"]
    if (root.mediaType === "comic") return ["reading", "read", "dropped", "backlog"]
    return ["done"]
  }

  // An edited note may carry a status typed by hand in Obsidian; keep it
  // selectable instead of silently swapping it for a default.
  function statusChoices() {
    var options = root.statusOptions()
    if (root.statusValue && options.indexOf(root.statusValue) < 0) options = options.concat([root.statusValue])
    return options
  }

  // ------------------------------------------------------------ form state
  //
  // Most controls own their own text/value and get read straight off their
  // ids at save time; rating and status need a QML-side value because
  // PanelSlider/Dropdown need something to bind their initial value to
  // when the type-driven default changes.
  property real ratingValue: 0
  property string statusValue: ""
  property bool rewatchValue: false
  property string savedConfirmation: ""
  property bool hasActiveSelection: false

  function resetFormFields() {
    root.ratingValue = 0
    root.statusValue = root.defaultStatus()
    root.rewatchValue = false
    reviewField.text = ""
    hoursPlayedField.field.value = 0
    platformField.text = ""
    formatField.text = ""
    labelField.text = ""
    writerField.text = ""
    artistField.text = ""
  }

  function buildFields() {
    return {
      rating: root.ratingValue,
      review: reviewField.text,
      status: root.statusValue,
      dateLogged: "",
      hoursPlayed: hoursPlayedField.field.value,
      platform: platformField.text,
      rewatch: root.rewatchValue,
      format: formatField.text,
      label: labelField.text,
      writer: writerField.text,
      artist: artistField.text
    }
  }

  function submitSave() {
    var fields = root.buildFields()
    // async; onSaveCountChanged below confirms it
    if (root.editingEntry) {
      // Fill in the cover and source_id that notes written before those
      // fields existed are missing: from the search result this entry was
      // opened under, or else from the service's title lookup.
      var f = root.editingEntry.fields || {}
      var hit = root.editReturnsToForm ? root.selected() : null
      var found = root.lookedUp(root.editingEntry)
      if (!f.cover) fields.cover = (hit && hit.coverUrl) || (found && found.coverUrl) || ""
      if (!f.source_id) fields.sourceId = (hit && root.service.sourceIdFor(root.mediaType, hit)) || (found && found.sourceId) || ""
      root.service.updateEntry(root.editingEntry.path, fields)
    }
    else root.saveSelected(fields)
  }

  Connections {
    target: root.service
    function onSaveCountChanged() {
      if (!root.hasActiveSelection) return
      var wasEdit = root.editingEntry !== null
      root.hasActiveSelection = false
      root.editingEntry = null
      root.savedConfirmation = (wasEdit ? "Updated " : "Saved ") + (root.service ? root.service.lastSavedPath : "")
      confirmationTimer.restart()
    }
  }

  Timer {
    id: confirmationTimer
    interval: 6000
    onTriggered: root.savedConfirmation = ""
  }

  Timer {
    id: searchDebounce
    interval: 400
    onTriggered: root.runSearch(searchField.text)
  }

  // A cover image, or an empty tinted slot while it loads or if there's
  // none. Inline components don't see this file's ids, hence `tint`.
  component Cover: Rectangle {
    id: cover
    property string url: ""
    property color tint: "white"
    radius: Style.spacing.xxs
    color: Qt.rgba(tint.r, tint.g, tint.b, 0.08)
    clip: true

    Image {
      anchors.fill: parent
      source: cover.url
      asynchronous: true
      cache: true
      fillMode: Image.PreserveAspectCrop
      sourceSize.width: cover.width * 2
      sourceSize.height: cover.height * 2
      visible: status === Image.Ready
    }
  }

  // ----------------------------------------------------------- appearance
  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Color.menu.scrim
  property color selectedBackground: Color.menu.selectedBackground
  property color selectedText: Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property int cardWidth: Math.min(Style.space(440), panel.width - Style.gapsOut * 2)
  property int cardHeight: Math.min(Style.space(600), panel.height - Style.gapsOut * 2)

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "aimabe-mediajournal"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    Shortcut {
      sequence: "Escape"
      onActivated: root.dismiss()
    }

    BorderSurface {
      id: card
      width: root.cardWidth
      height: root.cardHeight
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding

      MouseArea { anchors.fill: parent; onClicked: {} }   // swallow clicks, don't dismiss

      Flickable {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          width: parent.width
          spacing: Style.spacing.md

          // -------------------------------------------------------- header
          Row {
            width: parent.width
            spacing: Style.spacing.md

            Dropdown {
              width: parent.width - closeButton.width - Style.spacing.md
              showLabel: false
              value: root.mediaType
              options: root.mediaTypes
              onChanged: function(v) { root.changeMediaType(v) }
            }

            Button {
              id: closeButton
              text: "✕"
              focusable: true
              onClicked: root.dismiss()
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.service && root.service.configError !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.service ? root.service.configError : ""
            color: root.foreground
            opacity: 0.75
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }

          // -------------------------------------------------- search + list
          Column {
            width: parent.width
            spacing: Style.spacing.md
            visible: !root.hasActiveSelection

            TextField {
              id: searchField
              width: parent.width
              placeholderText: "Search " + root.mediaType + "s…"
              onTextChanged: searchDebounce.restart()
              Keys.onReturnPressed: { searchDebounce.stop(); root.runSearch(text) }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: root.searchBusy() || root.searchError() !== ""
              text: root.searchBusy() ? "Searching…" : root.searchError()
              color: root.foreground
              opacity: 0.7
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              visible: root.showingRecent
              text: root.recentEntries().length ? "Recent" : "Nothing logged yet. Search to log your first " + root.mediaType + "."
              color: Qt.darker(root.foreground, 1.4)
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }

            Column {
              width: parent.width
              spacing: Style.spacing.xxs

              Repeater {
                model: root.listModel()

                Rectangle {
                  id: resultRow
                  required property var modelData
                  width: content.width
                  height: Math.max(rowCover.height, resultCol.implicitHeight) + Style.spacing.controlPaddingY * 2
                  radius: root.cornerRadius
                  color: rowHover.hovered ? root.selectedBackground : "transparent"

                  HoverHandler { id: rowHover }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.activateRow(resultRow.modelData)
                  }

                  Cover {
                    id: rowCover
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.spacing.controlPaddingX
                    height: Style.space(44)
                    width: root.coverWidth(height)
                    url: root.rowCover(resultRow.modelData)
                    tint: root.foreground
                  }

                  Column {
                    id: resultCol
                    anchors.left: rowCover.right
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.spacing.md
                    anchors.rightMargin: Style.spacing.controlPaddingX
                    spacing: Style.spacing.xxs

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: root.rowTitle(resultRow.modelData)
                      color: root.foreground
                      elide: Text.ElideRight
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                    }
                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: root.rowSubtitle(resultRow.modelData)
                      color: root.foreground
                      opacity: 0.65
                      elide: Text.ElideRight
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }
          }

          // --------------------------------------------------------- form
          Column {
            width: parent.width
            spacing: Style.spacing.md
            visible: root.hasActiveSelection

            Row {
              width: parent.width
              spacing: Style.spacing.md

              Button {
                id: backButton
                text: "‹ Back"
                focusable: true
                onClicked: root.backToSearch()
              }

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - backButton.width - Style.spacing.md
                elide: Text.ElideRight
                visible: root.editingEntry !== null
                text: root.editingEntry ? "Editing your entry from " + (root.editingEntry.fields.date_logged || "?") : ""
                color: root.foreground
                opacity: 0.7
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
            }

            Row {
              width: parent.width
              spacing: Style.spacing.md

              Cover {
                id: headerCover
                height: Style.space(120)
                width: root.coverWidth(height)
                url: root.headerInfo().cover
                tint: root.foreground
              }

              Column {
                width: parent.width - headerCover.width - Style.spacing.md
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.spacing.xxs

                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  wrapMode: Text.WordWrap
                  maximumLineCount: 3
                  elide: Text.ElideRight
                  text: root.headerInfo().title
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Text {
                  textFormat: Text.PlainText
                  width: parent.width
                  elide: Text.ElideRight
                  text: {
                    var h = root.headerInfo()
                    return [h.year, h.creator].filter(function(x) { return x !== "" && x !== null }).join(" · ")
                  }
                  color: root.foreground
                  opacity: 0.65
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            // Past entries for the selected search result; click one to
            // edit it instead of logging a new entry.
            Column {
              width: parent.width
              spacing: Style.spacing.xxs
              visible: root.pastEntries().length > 0

              Text {
                textFormat: Text.PlainText
                text: "Logged before · click to view or edit"
                color: Qt.darker(root.foreground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              Repeater {
                model: root.pastEntries()

                Rectangle {
                  id: pastRow
                  required property var modelData
                  width: content.width
                  height: pastCol.implicitHeight + Style.spacing.controlPaddingY * 2
                  radius: root.cornerRadius
                  color: pastHover.hovered ? root.selectedBackground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)

                  HoverHandler { id: pastHover }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openEntry(pastRow.modelData, true)
                  }

                  Column {
                    id: pastCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.spacing.controlPaddingX
                    anchors.rightMargin: Style.spacing.controlPaddingX
                    spacing: Style.spacing.xxs

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: root.entrySubtitle(pastRow.modelData)
                      color: root.foreground
                      font.family: Style.font.family
                      font.pixelSize: Style.font.bodySmall
                    }
                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      visible: text !== ""
                      text: pastRow.modelData.review || ""
                      wrapMode: Text.WordWrap
                      maximumLineCount: 2
                      elide: Text.ElideRight
                      color: root.foreground
                      opacity: 0.65
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.spacing.labelGap

              Text {
                textFormat: Text.PlainText
                text: "Rating"
                color: Qt.darker(root.foreground, 1.4)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }

              Row {
                width: parent.width
                spacing: Style.spacing.md

                PanelSlider {
                  width: parent.width - Style.space(60)
                  minimum: 0
                  maximum: 5
                  step: 0.5
                  value: root.ratingValue
                  onMoved: function(v) { root.ratingValue = Math.round(v * 2) / 2 }
                  onReleased: function(v) { root.ratingValue = Math.round(v * 2) / 2 }
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: "★ " + root.ratingValue.toFixed(1)
                  color: root.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
              }
            }

            // Multi-line so past reviews can be read and extended; qs.Ui has
            // no text-area control, so this is a bordered TextEdit.
            Rectangle {
              width: parent.width
              height: Math.max(Style.space(96), reviewField.contentHeight + Style.spacing.inputPaddingY * 2)
              radius: root.cornerRadius
              color: "transparent"
              border.width: Math.max(1, Style.space(1))
              border.color: reviewField.activeFocus ? Color.accent : root.border

              TextEdit {
                id: reviewField
                anchors.fill: parent
                anchors.leftMargin: Style.spacing.controlPaddingX
                anchors.rightMargin: Style.spacing.controlPaddingX
                anchors.topMargin: Style.spacing.inputPaddingY
                anchors.bottomMargin: Style.spacing.inputPaddingY
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.Wrap
                selectByMouse: true
                activeFocusOnTab: true
                color: root.foreground
                selectionColor: root.selectedBackground
                selectedTextColor: root.selectedText
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              Text {
                textFormat: Text.PlainText
                anchors.fill: reviewField
                visible: reviewField.text === "" && !reviewField.activeFocus
                text: "Review (Enter for a new line)"
                color: root.foreground
                opacity: 0.45
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }

            Dropdown {
              width: parent.width
              label: "Status"
              value: root.statusValue
              options: root.statusChoices()
              onChanged: function(v) { root.statusValue = v }
            }

            // --------------------------------------------- game-specific
            Row {
              width: parent.width
              spacing: Style.spacing.md
              visible: root.mediaType === "game"

              NumberField {
                id: hoursPlayedField
                label: "Hours played"
                from: 0
                to: 5000
                value: 0
              }

              TextField {
                id: platformField
                width: parent.width - hoursPlayedField.width - Style.spacing.md
                placeholderText: "Platform (defaults to " + ((root.selected() && root.mediaType === "game" && root.selected().platforms) || "—") + ")"
              }
            }

            // --------------------------------------------- film-specific
            Row {
              width: parent.width
              spacing: Style.spacing.md
              visible: root.mediaType === "film"

              ToggleSwitch {
                checked: root.rewatchValue
                onToggled: root.rewatchValue = !root.rewatchValue
              }
              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: "Rewatch"
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
            }

            // --------------------------------------------- book/music-specific
            //
            // Both write to the shared `format` frontmatter field — one
            // TextField, placeholder text and visibility keyed off type,
            // rather than a separate field per type mirrored into a hidden
            // one. `label` is music-only.
            TextField {
              id: formatField
              width: parent.width
              visible: root.mediaType === "book" || root.mediaType === "music"
              placeholderText: root.mediaType === "music" ? "Format (vinyl, CD, digital…)" : "Format (paperback, hardcover, ebook…)"
            }

            TextField {
              id: labelField
              width: parent.width
              visible: root.mediaType === "music"
              placeholderText: "Label"
            }

            // --------------------------------------------- comic-specific
            Row {
              width: parent.width
              spacing: Style.spacing.md
              visible: root.mediaType === "comic"

              TextField {
                id: writerField
                width: (parent.width - Style.spacing.md) / 2
                placeholderText: "Writer"
              }
              TextField {
                id: artistField
                width: (parent.width - Style.spacing.md) / 2
                placeholderText: "Artist"
              }
            }

            Row {
              width: parent.width
              spacing: Style.spacing.md

              Button {
                text: root.service && root.service.saveBusy ? "Saving…" : (root.editingEntry ? "Save changes" : "Save")
                bordered: true
                focusable: true
                enabled: !(root.service && root.service.saveBusy)
                onClicked: root.submitSave()
              }
            }

          }

          // Outside the form: a successful save closes the form, and the
          // confirmation should still be visible after it does.
          Text {
            textFormat: Text.PlainText
            width: parent.width
            wrapMode: Text.WordWrap
            visible: root.savedConfirmation !== "" || (root.service && root.service.saveError !== "")
            text: (root.service && root.service.saveError) || root.savedConfirmation
            color: root.foreground
            opacity: 0.8
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
          }
        }
      }
    }
  }
}
