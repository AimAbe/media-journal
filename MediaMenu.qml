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
    root.savedConfirmation = ""
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
    root.savedConfirmation = ""
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
    root.hasActiveSelection = false
    root.savedConfirmation = ""
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
    root.saveSelected(fields)   // async; onLastSavedPathChanged below confirms it
  }

  Connections {
    target: root.service
    function onLastSavedPathChanged() {
      if (!root.hasActiveSelection) return
      root.hasActiveSelection = false
      root.savedConfirmation = "Saved " + (root.service ? root.service.lastSavedPath : "")
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

            Column {
              width: parent.width
              spacing: Style.spacing.xxs

              Repeater {
                model: root.results()

                Rectangle {
                  id: resultRow
                  required property var modelData
                  width: content.width
                  height: resultCol.implicitHeight + Style.spacing.controlPaddingY * 2
                  radius: root.cornerRadius
                  color: rowHover.hovered ? root.selectedBackground : "transparent"

                  HoverHandler { id: rowHover }
                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selectResult(resultRow.modelData)
                  }

                  Column {
                    id: resultCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.spacing.controlPaddingX
                    anchors.rightMargin: Style.spacing.controlPaddingX
                    spacing: Style.spacing.xxs

                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: resultRow.modelData.title
                      color: root.foreground
                      elide: Text.ElideRight
                      font.family: Style.font.family
                      font.pixelSize: Style.font.body
                    }
                    Text {
                      textFormat: Text.PlainText
                      width: parent.width
                      text: root.resultSubtitle(resultRow.modelData)
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
                text: "‹ Back"
                focusable: true
                onClicked: root.backToSearch()
              }

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - Style.space(80)
                elide: Text.ElideRight
                text: {
                  var s = root.selected()
                  return s ? s.title + (s.year ? " (" + s.year + ")" : "") : ""
                }
                color: root.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.title
                font.bold: true
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

            TextField {
              id: reviewField
              width: parent.width
              placeholderText: "Review (goes under the heading in the note body)"
            }

            Dropdown {
              width: parent.width
              label: "Status"
              value: root.statusValue
              options: root.statusOptions()
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
                text: root.service && root.service.saveBusy ? "Saving…" : "Save"
                bordered: true
                focusable: true
                enabled: !(root.service && root.service.saveBusy)
                onClicked: root.submitSave()
              }
            }

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
}
