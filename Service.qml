import QtQuick
import Quickshell.Io

// Records the clipboard. Two `wl-paste --watch` processes, one for text and
// one for images, hand every new copy to scripts/clip24, which stores it in
// ~/.local/state/omarchy/clip24 and drops what has expired. The shell runs
// this once; the bar widget (Panel.qml, one per monitor) only reads.
//
// Lifecycle: watchers left behind by an earlier shell instance, or by an older
// version of this plugin, are reaped before ours start. `setpriv --pdeathsig`
// makes the kernel stop ours whenever the shell exits, however it exits, so
// they cannot pile up across restarts. A watcher that exits is restarted,
// backing off up to a minute while it keeps failing.
Item {
  id: root

  readonly property string helper: Qt.resolvedUrl("scripts/clip24").toString().replace(/^file:\/\//, "")

  function watchCommand(kind) {
    return ["setpriv", "--pdeathsig", "TERM", "wl-paste", "--type", kind, "--watch", root.helper, "capture", kind]
  }

  function watchExited(watch, timer, code) {
    // Running for a while and then exiting is a hiccup: come back in a second.
    // Exiting right after starting means something is wrong: back off.
    var quick = Date.now() - watch.startedAt < 10000
    watch.delay = quick ? Math.min(watch.delay * 2, 60000) : 1000
    if (quick && watch.delay >= 8000)
      console.warn("techspawn.cliphistory: wl-paste --type " + watch.kind + " keeps exiting (code " + code + "), retrying in " + watch.delay / 1000 + " s")
    timer.interval = watch.delay
    timer.restart()
  }

  Process {
    id: reaper
    // Anchored on argv[0], so only wl-paste processes match, not a shell or
    // editor that merely has this text on its command line.
    command: ["pkill", "-f", "^[^ ]*wl-paste .*--watch .*/clip24 capture"]
    running: true
    onExited: {
      textWatch.start()
      imageWatch.start()
      pruneProc.running = true
    }
  }

  Process {
    id: textWatch
    readonly property string kind: "text"
    property real startedAt: 0
    property int delay: 1000
    function start() { startedAt = Date.now(); running = true }
    command: root.watchCommand(kind)
    onExited: function(code) { root.watchExited(textWatch, textRestart, code) }
  }

  // "image" lets wl-paste pick whichever image type the source offers
  // (PNG, JPEG, WebP, GIF, ...); the helper reads the format from the data.
  Process {
    id: imageWatch
    readonly property string kind: "image"
    property real startedAt: 0
    property int delay: 1000
    function start() { startedAt = Date.now(); running = true }
    command: root.watchCommand(kind)
    onExited: function(code) { root.watchExited(imageWatch, imageRestart, code) }
  }

  Timer { id: textRestart; onTriggered: if (!textWatch.running) textWatch.start() }
  Timer { id: imageRestart; onTriggered: if (!imageWatch.running) imageWatch.start() }

  // Expire old entries even when nothing new is copied.
  Process { id: pruneProc; command: [root.helper, "prune"] }
  Timer {
    interval: 3600000
    repeat: true
    running: true
    onTriggered: if (!pruneProc.running) pruneProc.running = true
  }
}
