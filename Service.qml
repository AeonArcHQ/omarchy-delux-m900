import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// Mouse state for one bar entry. `m900-hid watch` stays running for the
// battery and the mouse's own DPI and rate changes; `m900-hid apply` sends one
// change at a time. The mouse cannot be read back, so the profile shown is the
// last one the mouse acknowledged, saved by the helper.
Item {
  id: root

  property var battery: ({ connection: "starting", state: "", level: -1 })
  property var profile: Model.normalizeProfile(null)
  property bool busy: false
  property string lastError: ""

  readonly property string helperPath: String(Qt.resolvedUrl("m900-hid")).replace(/^file:\/\//, "")
  readonly property string profilePath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state"))
    + "/delux-m900/profile.json"

  property var _pending: null

  // `path` is a profile field ("polling") or a light field ("light.mode").
  function set(path, value) {
    var next = Model.withValue(root.profile, path, value)
    var packets = Model.packetsFor(path.split(".")[0], next)
    root.send(next, packets)
  }

  function setStageDpi(index, dpi) {
    var values = root.profile.dpi.slice()
    values[index] = dpi
    root.set("dpi", values)
  }

  function setButton(slot, option) {
    var next = Model.withButton(root.profile, slot, option)
    if (next === null) {
      root.lastError = "Some button has to keep the left click."
      return
    }
    root.send(next, Model.packetsFor("buttons", next))
  }

  function resetDefaults() {
    root.send(Model.normalizeProfile(Model.FACTORY), Model.factoryPackets())
  }

  // One job waits while another is in flight. A newer change folds into it:
  // the newest profile holds every change, and the job sends each report that
  // any of them touched.
  function send(next, packets) {
    if (packets.length === 0) return
    root.profile = next
    root.lastError = ""
    var waiting = root._pending === null ? [] : root._pending.packets
    root._pending = { profile: next, packets: Model.mergePackets(waiting, packets, next) }
    root.flush()
  }

  function flush() {
    if (applyProcess.running || root._pending === null) return
    var job = root._pending
    root._pending = null
    root.busy = true
    applyProcess.command = [root.helperPath, "apply", JSON.stringify(job.profile)].concat(job.packets)
    applyProcess.running = true
  }

  function loadProfile(text) {
    var raw = null
    try { raw = JSON.parse(String(text || "")) } catch (error) { raw = null }
    root.profile = Model.normalizeProfile(raw)
  }

  function onWatchLine(line) {
    root.battery = Model.applyLine(root.battery, line)
    var moved = Model.applyEvent(root.profile, line)
    if (moved === null || JSON.stringify(moved) === JSON.stringify(root.profile)) return
    root.profile = moved
    if (!saveProcess.running) {
      saveProcess.command = [root.helperPath, "save", JSON.stringify(moved)]
      saveProcess.running = true
    }
  }

  FileView {
    id: profileFile
    path: root.profilePath
    watchChanges: true
    printErrors: false
    onLoaded: if (!applyProcess.running && root._pending === null) root.loadProfile(text())
    // No file yet: nothing was applied from Linux, so the mouse is on what
    // the factory restore of docs/re/findings.md left it with.
    onLoadFailed: if (!applyProcess.running && root._pending === null) root.loadProfile("")
    onFileChanged: reload()
  }

  Process {
    id: watchProcess
    command: [root.helperPath, "watch"]
    running: true
    stdout: SplitParser {
      onRead: function(line) { root.onWatchLine(line) }
    }
    // The helper retries on its own; it only exits on a crash. Start it again
    // after a pause instead of spinning.
    onExited: function(exitCode) {
      root.battery = Model.applyLine(root.battery, "")
      restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    interval: 5000
    onTriggered: watchProcess.running = true
  }

  Process {
    id: applyProcess
    running: false
    command: []
    stdout: StdioCollector { id: applyStdout; waitForEnd: true }
    onExited: function(exitCode) {
      root.busy = false
      root.lastError = Model.applyError(applyStdout.text)
      // A refused change leaves the mouse on the saved profile; show that one.
      if (root.lastError !== "" && root._pending === null) profileFile.reload()
      root.flush()
    }
  }

  Process {
    id: saveProcess
    running: false
    command: []
  }
}
