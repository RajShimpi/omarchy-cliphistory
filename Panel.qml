import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Clipboard history in the bar. Service.qml records; this widget only reads
// and acts through scripts/clip24, and only while you look at it: when the
// panel opens, when the history changes while it is open, and when you hover
// the icon (for the count in the tooltip). There is one of these per monitor,
// so it never records anything itself.
Panel {
  id: root
  moduleName: "techspawn.cliphistory"
  ipcTarget: "techspawn.cliphistory"
  manageIpc: true

  readonly property string helper: Qt.resolvedUrl("scripts/clip24").toString().replace(/^file:\/\//, "")
  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(root.fg, 1.6)
  readonly property color accent: Commons.Color.accent
  readonly property string font: root.bar ? root.bar.fontFamily : Style.font.family

  // Nerd Font (Material Design) glyphs: md-clipboard_text_clock, md-text_box_outline, md-link,
  // md-image_outline, md-pin, md-pin_off, md-delete_outline, md-keyboard_outline,
  // md-delete_sweep_outline, md-pencil.
  readonly property var icons: ({ bar: 0xf18f9, text: 0xf09ed, link: 0xf0337, image: 0xf0976, pin: 0xf0403,
                                   unpin: 0xf0404, del: 0xf09e7, type: 0xf097b, clear: 0xf0c62, edit: 0xf03eb })
  function glyph(name) { return String.fromCodePoint(icons[name]) }

  property var items: []
  property int total: 0
  property int pinnedCount: 0
  property bool recording: true
  property var cfg: ({ retentionHours: 24, maxItems: 500, images: true })
  property string dbPath: ""
  property bool loaded: false
  property real loadedAt: 0
  property bool refreshAgain: false
  property var queue: []
  property string query: ""
  property int cursor: 0
  property string focusId: ""
  property real now: Date.now() / 1000

  readonly property var rows: {
    var q = query.trim().toLowerCase()
    if (q === "") return items
    var words = q.split(/\s+/)
    return items.filter(function(it) {
      return words.every(function(w) { return (it.hay || "").indexOf(w) >= 0 })
    })
  }
  readonly property var hot: rows.length ? rows[Math.min(cursor, rows.length - 1)] : null
  readonly property bool hasPinnedRows: rows.length > 0 && rows[0].pinned === true
  readonly property int unpinnedCount: Math.max(0, total - pinnedCount)
  readonly property string keptFor: {
    var h = cfg.retentionHours || 24
    return h % 24 === 0 && h >= 48 ? (h / 24) + " days" : h + " h"
  }
  readonly property string tooltip: !loaded ? "Clipboard history"
    : "Clipboard history · " + total + (total === 1 ? " item" : " items")
      + (pinnedCount ? " · " + pinnedCount + " pinned" : "") + (recording ? "" : " · not recording")

  // ---------- helper ----------

  function refresh() {
    if (listProc.running) { refreshAgain = true; return }
    listProc.running = true
  }

  function loadPanel(text) {
    try {
      var d = JSON.parse(text)
      items = d.items || []
      total = d.total || 0
      pinnedCount = d.pinned || 0
      recording = d.recording !== false
      cfg = d.settings || cfg
      dbPath = d.db || ""
      loaded = true
      loadedAt = Date.now()
    } catch (e) {
      console.warn("techspawn.cliphistory: bad helper output: " + e)
    }
    if (focusId !== "") {
      for (var i = 0; i < rows.length; i++) if (rows[i].id === focusId) cursor = i
      focusId = ""
    }
    cursor = Math.max(0, Math.min(cursor, rows.length - 1))
    if (button.tooltipHovered && root.bar) root.bar.showTooltip(button, root.tooltip)
  }

  // Delete, pin and clear run one after another, then the list is re-read.
  function helperCall(args) {
    queue = queue.concat([args])
    if (!actProc.running) runNext()
  }
  function runNext() {
    if (!queue.length) { refresh(); return }
    actProc.command = [root.helper].concat(queue[0])
    queue = queue.slice(1)
    actProc.running = true
  }

  // ---------- actions ----------

  function copy(it) {
    if (!it) return
    Quickshell.execDetached([root.helper, "copy", it.id])
    root.close()
  }

  // Types into the window that had focus; the helper waits for the panel to close.
  function typeIt(it) {
    if (!it) return
    root.close()
    Quickshell.execDetached([root.helper, "type", it.id])
  }

  function remove(it) {
    if (!it) return
    items = items.filter(function(x) { return x.id !== it.id })
    total = Math.max(0, total - 1)
    if (it.pinned) pinnedCount = Math.max(0, pinnedCount - 1)
    cursor = Math.max(0, Math.min(cursor, rows.length - 1))
    helperCall(["delete", it.id])
  }

  function byNewest(a, b) { return b.at - a.at }

  function togglePin(it) {
    if (!it) return
    var on = !it.pinned
    var moved = Object.assign({}, it, { pinned: on })
    var others = items.filter(function(x) { return x.id !== it.id })
    var pinned = others.filter(function(x) { return x.pinned })
    var rest = others.filter(function(x) { return !x.pinned })
    if (on) pinned.push(moved)
    else rest.push(moved)
    pinned.sort(byNewest)
    rest.sort(byNewest)
    focusId = it.id
    items = pinned.concat(rest)
    pinnedCount = pinned.length
    for (var i = 0; i < rows.length; i++) if (rows[i].id === it.id) cursor = i
    helperCall(["pin", it.id, on ? "on" : "off"])
  }

  function askClear() {
    if (unpinnedCount === 0) return
    confirm.selectedIndex = 0
    confirm.opened = true
    keys.forceActiveFocus()
  }

  function clearAll() {
    items = items.filter(function(x) { return x.pinned })
    total = items.length
    cursor = 0
    helperCall(["clear"])
  }

  function editSettings() {
    Quickshell.execDetached([root.helper, "edit"])
    root.close()
  }

  function move(step) {
    var n = rows.length
    if (!n) return
    cursor = Math.max(0, Math.min(n - 1, cursor + step))
  }

  function startSearch(ch) {
    search.forceActiveFocus()
    if (ch) {
      search.text = search.text + ch
      search.cursorPosition = search.text.length
    }
  }

  // ---------- formatting ----------

  function ago(at) {
    var s = Math.max(0, now - at)
    if (s < 45) return "just now"
    if (s < 3600) return Math.max(1, Math.round(s / 60)) + " min ago"
    if (s < 86400) return Math.floor(s / 3600) + " h ago"
    var d = Math.floor(s / 86400)
    return d === 1 ? "yesterday" : d + " days ago"
  }

  function size(bytes) {
    if (bytes < 1024) return bytes + " B"
    if (bytes < 1048576) return Math.round(bytes / 1024) + " KB"
    return (bytes / 1048576).toFixed(1) + " MB"
  }

  // "org.mozilla.firefox" -> "firefox"
  function appName(app) { return app ? String(app).split(".").pop() : "" }

  function title(it) {
    if (it.type === "image") return "Image" + (it.width ? "  " + it.width + "×" + it.height : "")
    return it.preview || ""
  }

  function subtitle(it) {
    var parts = [ago(it.at)]
    if (it.app) parts.push(appName(it.app))
    if (it.type === "image") parts.push(size(it.size || 0))
    else {
      if (it.lines > 1) parts.push(it.lines + " lines")
      parts.push(it.chars + (it.chars === 1 ? " char" : " chars"))
    }
    return parts.join("  ·  ")
  }

  // ---------- keys ----------

  // List mode: the panel opens here. Letters that are not commands start a search.
  function listKey(e) {
    if (search.activeFocus) return
    if (confirm.opened) {
      if (confirm.handleKey(e)) e.accepted = true
      return
    }
    var k = e.key, t = e.text
    var shift = e.modifiers & Qt.ShiftModifier
    var mod = e.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)
    if (k === Qt.Key_Escape) { if (search.text !== "") search.text = ""; else root.close() }
    else if (k === Qt.Key_Down || (!mod && t === "j")) move(1)
    else if (k === Qt.Key_Up || (!mod && t === "k")) move(-1)
    else if (k === Qt.Key_PageDown) move(8)
    else if (k === Qt.Key_PageUp) move(-8)
    else if (k === Qt.Key_Home || (!mod && t === "g")) cursor = 0
    else if (k === Qt.Key_End || (!mod && t === "G")) cursor = Math.max(0, rows.length - 1)
    else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (shift) typeIt(hot); else copy(hot) }
    else if (k === Qt.Key_Delete || (!mod && t === "x")) remove(hot)
    else if (!mod && t === "p") togglePin(hot)
    else if (!mod && t === "C") askClear()
    else if (!mod && t === "/") startSearch("")
    else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) root.switchPanel(k === Qt.Key_Backtab || shift ? -1 : 1)
    else if (!mod && t.length === 1 && t > " ") startSearch(t)
    else return
    e.accepted = true
  }

  // Search mode: typing filters; arrows still move, Tab goes back to the list
  // (keeping the filter) so x and p work on what you found.
  function searchKey(e) {
    var k = e.key
    var shift = e.modifiers & Qt.ShiftModifier
    var ctrl = e.modifiers & Qt.ControlModifier
    if (k === Qt.Key_Escape) {
      if (search.text === "") root.close()
      search.text = ""
      keys.forceActiveFocus()
    }
    else if (k === Qt.Key_Down || (ctrl && k === Qt.Key_J)) move(1)
    else if (k === Qt.Key_Up || (ctrl && k === Qt.Key_K)) move(-1)
    else if (k === Qt.Key_PageDown) move(8)
    else if (k === Qt.Key_PageUp) move(-8)
    else if (k === Qt.Key_Return || k === Qt.Key_Enter) { if (shift) typeIt(hot); else copy(hot) }
    else if (ctrl && k === Qt.Key_P) togglePin(hot)
    else if (k === Qt.Key_Tab || k === Qt.Key_Backtab) keys.forceActiveFocus()
    else return
    e.accepted = true
  }

  function ensureVisible() {
    if (rows.length) list.positionViewAtIndex(Math.min(cursor, rows.length - 1), ListView.Contain)
  }
  onCursorChanged: {
    pointerGate.reset()
    ensureVisible()
  }
  // A new model scrolls the list back to the top; bring the cursor row back.
  onRowsChanged: Qt.callLater(root.ensureVisible)
  onQueryChanged: cursor = 0

  onOpenedChanged: {
    if (opened) {
      search.text = ""
      cursor = 0
      now = Date.now() / 1000
      refresh()
    } else {
      confirm.opened = false
    }
  }

  // ---------- processes ----------

  Process {
    id: listProc
    command: [root.helper, "panel"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.loadPanel(text)
    }
    onExited: if (root.refreshAgain) { root.refreshAgain = false; root.refresh() }
  }

  Process {
    id: actProc
    onExited: root.runNext()
  }

  // Something copied while the panel is open shows up right away.
  FileView {
    path: root.dbPath
    watchChanges: root.dbPath !== ""
    printErrors: false
    onFileChanged: {
      reload()
      if (root.opened) refreshSoon.restart()
    }
  }
  Timer { id: refreshSoon; interval: 300; onTriggered: root.refresh() }

  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    onTriggered: root.now = Date.now() / 1000
  }

  PointerMoveGate { id: pointerGate; referenceItem: list }

  // ---------- bar ----------

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph("bar")
    tooltipText: root.tooltip
    onPressed: function(b) { root.toggle() }
    onTooltipHoveredChanged: if (tooltipHovered && Date.now() - root.loadedAt > 5000) root.refresh()
  }

  // ---------- panel ----------

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(Math.max(column.implicitHeight, confirm.opened ? Style.space(180) : 0))

    Item {
      id: keys
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(e) { root.listKey(e) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        // ---------- header ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(hero.implicitHeight, tools.implicitHeight)

          Row {
            id: hero
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(12)
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.glyph("bar")
              color: root.fg
              font.family: root.font
              font.pixelSize: Style.font.display
            }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)
              Text {
                text: "Clipboard"
                color: root.fg
                font.family: root.font
                font.pixelSize: Style.font.title
                font.bold: true
              }
              Text {
                text: (!root.loaded ? "loading…"
                       : root.total + (root.total === 1 ? " item" : " items") + " · kept " + root.keptFor
                         + (root.pinnedCount ? " · " + root.pinnedCount + " pinned" : "")).toUpperCase()
                color: Qt.darker(root.fg, 1.4)
                font.family: root.font
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }
            }
          }

          Row {
            id: tools
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)
            Button {
              iconText: root.glyph("clear")
              text: "Clear"
              fontSize: Style.font.bodySmall
              foreground: root.fg
              fontFamily: root.font
              bordered: true
              enabled: root.unpinnedCount > 0
              opacity: enabled ? 1 : 0.4
              tooltipText: "Delete everything except pinned items (Shift+C)"
              onClicked: root.askClear()
            }
            Button {
              iconText: root.glyph("edit")
              foreground: root.fg
              fontFamily: root.font
              tooltipText: "Settings: how long to keep, size limits, apps to ignore"
              onClicked: root.editSettings()
            }
          }
        }

        TextField {
          id: search
          width: parent.width
          placeholderText: "Search clipboard…   ( / )"
          foreground: root.fg
          font.family: root.font
          onTextChanged: root.query = text
          Keys.onPressed: function(e) { root.searchKey(e) }
        }

        Text {
          visible: root.loaded && !root.recording
          width: parent.width
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          text: "Not recording: no clipboard watcher is running. Check that wl-clipboard is installed and see journalctl --user for errors."
          color: Commons.Color.urgent
          font.family: root.font
          font.pixelSize: Style.font.bodySmall
        }

        // ---------- list ----------
        ListView {
          id: list
          visible: root.rows.length > 0
          width: parent.width
          height: Math.min(contentHeight, Style.space(460))
          model: root.rows
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          delegate: Item {
            id: row
            required property var modelData
            required property int index
            readonly property bool hot: root.cursor === index
            readonly property bool isImage: modelData.type === "image"
            readonly property bool showHeader: root.hasPinnedRows
              && (index === 0 || root.rows[index - 1].pinned !== modelData.pinned)
            width: ListView.view.width
            height: card.y + card.height + Style.space(2)

            PanelSectionHeader {
              id: header
              visible: row.showHeader
              height: visible ? implicitHeight + Style.space(4) : 0
              text: row.modelData.pinned ? "PINNED" : "RECENT"
              foreground: root.fg
              fontFamily: root.font
            }

            Rectangle {
              id: card
              y: header.height
              width: parent.width
              height: Math.max(lead.height, info.implicitHeight) + Style.space(12)
              radius: Style.cornerRadius
              color: row.hot ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : "transparent"
              border.width: row.hot ? 1 : 0
              border.color: root.accent

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: function(m) { if (pointerGate.moved(rowMouse, m)) root.cursor = row.index }
                onClicked: function(m) {
                  if (m.button === Qt.MiddleButton) root.togglePin(row.modelData)
                  else if (m.modifiers & Qt.ShiftModifier) root.typeIt(row.modelData)
                  else root.copy(row.modelData)
                }
              }

              Item {
                id: lead
                anchors.left: parent.left
                anchors.leftMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                width: row.isImage ? Style.space(84) : Style.space(20)
                height: row.isImage ? Style.space(52) : kindIcon.implicitHeight

                Rectangle {
                  visible: row.isImage
                  anchors.fill: parent
                  radius: Style.cornerRadius
                  color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.06)
                }
                Image {
                  id: thumb
                  visible: row.isImage
                  anchors.fill: parent
                  anchors.margins: 2
                  source: row.isImage ? "file://" + encodeURI(row.modelData.path) : ""
                  sourceSize.width: Style.space(168)
                  sourceSize.height: Style.space(104)
                  fillMode: Image.PreserveAspectFit
                  asynchronous: true
                  smooth: true
                }
                Text {
                  id: kindIcon
                  visible: !row.isImage || thumb.status === Image.Error
                  anchors.centerIn: parent
                  text: root.glyph(row.isImage ? "image" : row.modelData.url ? "link" : "text")
                  color: row.modelData.pinned ? root.accent : root.fg
                  font.family: root.font
                  font.pixelSize: Style.font.title
                }
              }

              Column {
                id: info
                anchors.left: lead.right
                anchors.leftMargin: Style.space(10)
                anchors.right: actions.left
                anchors.rightMargin: Style.space(8)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: root.title(row.modelData)
                  wrapMode: Text.Wrap
                  maximumLineCount: 2
                  elide: Text.ElideRight
                  color: root.fg
                  font.family: root.font
                  font.pixelSize: Style.font.bodySmall
                  font.bold: row.isImage
                }
                Text {
                  width: parent.width
                  textFormat: Text.PlainText
                  text: (row.modelData.pinned ? root.glyph("pin") + " " : "") + root.subtitle(row.modelData)
                  elide: Text.ElideRight
                  color: row.modelData.pinned ? root.accent : root.dim
                  font.family: root.font
                  font.pixelSize: Style.font.caption
                }
              }

              // Always takes its space, so hovering a row never re-wraps the text.
              Row {
                id: actions
                anchors.right: parent.right
                anchors.rightMargin: Style.space(10)
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(10)
                opacity: row.hot || rowMouse.containsMouse ? 1 : 0

                Repeater {
                  model: [
                    { id: "pin", icon: row.modelData.pinned ? "unpin" : "pin", tip: row.modelData.pinned ? "Unpin (p)" : "Pin: never expires (p)" },
                    { id: "type", icon: "type", tip: "Type it into the focused window (Shift+Enter)" },
                    { id: "del", icon: "del", tip: "Delete (x)" }
                  ]
                  delegate: Text {
                    id: actIcon
                    required property var modelData
                    visible: modelData.id !== "type" || !row.isImage
                    text: root.glyph(modelData.icon)
                    color: actArea.containsMouse ? root.accent : (row.hot ? root.fg : root.dim)
                    font.family: root.font
                    font.pixelSize: Style.font.body

                    MouseArea {
                      id: actArea
                      anchors.fill: parent
                      anchors.margins: -5
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (actIcon.modelData.id === "pin") root.togglePin(row.modelData)
                        else if (actIcon.modelData.id === "type") root.typeIt(row.modelData)
                        else root.remove(row.modelData)
                      }
                    }
                    PanelToolTip {
                      visible: actArea.containsMouse
                      text: actIcon.modelData.tip
                      fontFamily: root.font
                    }
                  }
                }
              }
            }
          }
        }

        // ---------- empty states ----------
        Text {
          visible: root.loaded && root.total > 0 && root.rows.length === 0
          width: parent.width
          topPadding: Style.space(10)
          bottomPadding: Style.space(10)
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: "Nothing matches “" + root.query.trim() + "”"
          color: root.dim
          font.family: root.font
          font.pixelSize: Style.font.bodySmall
        }

        Column {
          visible: root.loaded && root.total === 0
          width: parent.width
          spacing: Style.space(8)
          topPadding: Style.space(6)
          bottomPadding: Style.space(6)
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.glyph("bar")
            color: root.dim
            font.family: root.font
            font.pixelSize: Style.font.displayLarge
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: "Nothing copied in the last " + root.keptFor + ".\nCopy some text or an image and it shows up here."
            color: root.fg
            font.family: root.font
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: "Stored only on this computer. Password-manager copies are skipped."
            color: root.dim
            font.family: root.font
            font.pixelSize: Style.font.caption
          }
        }

        PanelSeparator { width: parent.width; foreground: root.fg }

        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: search.activeFocus
            ? "↵ copy · ⇧↵ type · ↑↓ move · ^P pin · Tab back to list · Esc clear"
            : "↵ copy · ⇧↵ type · j/k move · p pin · x delete · / search · ⇧C clear"
          color: root.dim
          font.family: root.font
          font.pixelSize: Style.font.caption
        }
      }

      ConfirmDialog {
        id: confirm
        anchors.fill: parent
        z: 10
        message: "Delete " + root.unpinnedCount + (root.unpinnedCount === 1 ? " item" : " items")
          + " from clipboard history?" + (root.pinnedCount ? " Pinned items stay." : "")
        confirmText: "Clear"
        foreground: root.fg
        fontFamily: root.font
        onCanceled: { opened = false; keys.forceActiveFocus() }
        onConfirmed: { opened = false; root.clearAll(); keys.forceActiveFocus() }
      }
    }
  }
}
