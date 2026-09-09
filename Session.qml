import QtQuick
import Quickshell
import Quickshell.Io
import "Format.js" as Format

// The keep-awake state machine: one logind inhibitor, an optional hold on
// omarchy's stay-awake indicator, and an optional gateway keepalive.
Item {
  id: root
  visible: false

  property var cfg: null
  property string pluginDir: ""

  // Side effects run on one bar instance only -- the widget exists once per
  // monitor. Unknown means yes, so a bad guess duplicates rather than silences.
  property bool primary: true

  readonly property bool ready: cfg !== null && cfg.loaded

  readonly property string durationKey: {
    var value = ready ? cfg.str("duration", "1h") : "1h"
    return Format.isDuration(value) ? value : "1h"
  }
  readonly property bool inhibitLid: ready && cfg.bool("inhibitLid", false)
  readonly property bool keepScreenOn: ready && cfg.bool("keepScreenOn", false)
  readonly property bool keepalive: ready ? cfg.bool("keepalive", true) : true

  property double now: Date.now()
  readonly property double expiresAt: ready ? cfg.num("expiresAt", 0, 0, 1e15) : 0
  readonly property bool wantActive: ready && cfg.bool("active", false)
  readonly property bool expired: wantActive && expiresAt > 0 && now >= expiresAt
  readonly property bool active: wantActive && !expired
  readonly property double remainingMs: active && expiresAt > 0 ? Math.max(0, expiresAt - now) : 0
  readonly property bool timed: active && expiresAt > 0

  // logind refused the lock, or the inhibitor died while still wanted.
  property bool inhibitorFailed: false
  readonly property bool inhibitorHeld: inhibitor.running && !inhibitorFailed

  property string screenOwner: "none"
  property bool screenHeld: false

  property string netGateway: ""
  property string netIface: ""
  property string netPowersave: "unknown"
  property string netPing: "skipped"
  property double netCheckedAt: 0

  readonly property string inhibitWhat: "sleep:idle" + (inhibitLid ? ":handle-lid-switch" : "")

  // ------------------------------------------------------------------ actions

  function start(key) {
    if (!ready) return
    var chosen = Format.isDuration(key) ? String(key) : root.durationKey
    var ms = Format.durationMs(chosen)
    root.now = Date.now()
    root.inhibitorFailed = false
    root.inhibitorRetries = 0
    cfg.setAll({ "active": true, "duration": chosen, "expiresAt": ms > 0 ? root.now + ms : 0 })
  }

  function stop() {
    if (!ready) return
    cfg.setAll({ "active": false, "expiresAt": 0 })
  }

  function toggle() {
    if (root.active) root.stop()
    else root.start(root.durationKey)
  }

  // Changing the preset while a session runs restarts the clock from now, which
  // is what "give me another two hours" means.
  function setDuration(key) {
    if (!ready || !Format.isDuration(key)) return
    if (root.active) root.start(key)
    else cfg.set("duration", String(key))
  }

  function setFlag(key, value) {
    if (!ready) return
    cfg.set(String(key), value === true)
  }

  // ---------------------------------------------------------------- claim id

  // A random public name, guarding nothing: it lets the helper tell a
  // stay-awake this plugin set apart from one the user set.
  function claimValid(value) {
    return /^[A-Za-z0-9._-]{8,64}$/.test(String(value || ""))
  }

  function ensureClaim() {
    var existing = ready ? cfg.str("claimId", "") : ""
    if (claimValid(existing)) return existing
    if (!ready) return ""
    var fresh = "insomnia-" + Date.now().toString(36)
      + "-" + Math.floor(Math.random() * 1000000000).toString(36)
    cfg.set("claimId", fresh)
    return fresh
  }

  // -------------------------------------------------------------- inhibitor

  property bool inhibitorRestarting: false

  function syncInhibitor() {
    if (!root.primary) return
    if (!root.active) {
      inhibitor.running = false
      return
    }
    if (inhibitor.running) {
      if (inhibitor.command.length > 1 && inhibitor.command[1] === "--what=" + root.inhibitWhat) return
      root.inhibitorRestarting = true
      inhibitor.running = false
      return
    }
    inhibitor.command = ["systemd-inhibit",
                         "--what=" + root.inhibitWhat,
                         "--who=Insomnia",
                         "--why=Insomnia keep-awake session",
                         "--mode=block",
                         "sleep", "infinity"]
    inhibitor.running = true
  }

  property string inhibitorError: ""

  // A refusal is often transient (a locked session, a shell restart). Retry with
  // backoff instead of staying failed until the user toggles by hand.
  property int inhibitorRetries: 0
  readonly property int inhibitorMaxRetries: 8

  Timer {
    id: inhibitorRetry
    repeat: false
    interval: Math.min(60000, 2000 * Math.pow(2, Math.max(0, root.inhibitorRetries - 1)))
    onTriggered: root.syncInhibitor()
  }

  Process {
    id: inhibitor
    running: false

    // Held again: clear the failure so the bar goes back to green.
    onStarted: root.inhibitorFailed = false

    // Without this the refusal reason is discarded and the failure is
    // undiagnosable from the log.
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.inhibitorError = Format.barSafe(text, 200)
    }

    onExited: function (exitCode) {
      if (root.inhibitorRestarting) {
        root.inhibitorRestarting = false
        Qt.callLater(root.syncInhibitor)
        return
      }
      // Gone while still wanted: report it rather than respawning into a loop.
      if (root.active && root.primary) {
        root.inhibitorFailed = true
        console.warn("insomnia: sleep inhibitor exited", exitCode, root.inhibitorError)
        if (root.inhibitorRetries < root.inhibitorMaxRetries) {
          root.inhibitorRetries++
          inhibitorRetry.restart()
        } else {
          console.warn("insomnia: giving up on the sleep inhibitor after",
                       root.inhibitorRetries, "attempts")
        }
      }
    }
  }

  // ------------------------------------------------------------ screen hold

  readonly property bool screenWanted: active && keepScreenOn
  property bool screenAsked: false
  property bool screenLastWant: false

  function syncScreen() {
    if (!root.primary || !root.ready) return
    if (screenProc.running) return
    var want = root.screenWanted
    if (root.screenAsked && root.screenLastWant === want) return
    var claim = root.ensureClaim()
    if (claim === "") return
    root.screenLastWant = want
    root.screenAsked = true
    screenProc.command = ["timeout", "-k", "2", "8",
                          root.pluginDir + "/bin/insomnia-screen",
                          want ? "hold" : "release", claim]
    screenProc.running = true
  }

  function applyScreenResult(text) {
    try {
      var parsed = JSON.parse(String(text || "").substring(0, 256))
      root.screenOwner = Format.whitelist(parsed.owner, 8)
      root.screenHeld = parsed.held === true && root.screenOwner === "self"
    } catch (error) {
      root.screenOwner = "unknown"
      root.screenHeld = false
    }
  }

  Process {
    id: screenProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyScreenResult(text)
    }
    onExited: function (exitCode) {
      if (exitCode !== 0) console.warn("insomnia: screen helper failed", exitCode)
      Qt.callLater(root.syncScreen)
    }
  }

  // -------------------------------------------------------------- network

  function probeNetwork() {
    if (!root.primary || netProc.running) return
    netProc.command = ["timeout", "-k", "2", "12",
                       root.pluginDir + "/bin/insomnia-net",
                       root.active && root.keepalive ? "ping" : "noping"]
    netProc.running = true
  }

  function applyNetResult(text) {
    try {
      var parsed = JSON.parse(String(text || "").substring(0, 512))
      root.netGateway = Format.whitelist(parsed.gateway, 15)
      root.netIface = Format.whitelist(parsed.iface, 15)
      root.netPowersave = Format.whitelist(parsed.powersave, 8)
      root.netPing = Format.whitelist(parsed.ping, 8)
      root.netCheckedAt = Date.now()
    } catch (error) {
      root.netPing = "unknown"
    }
  }

  Process {
    id: netProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyNetResult(text)
    }
  }

  Timer {
    id: netTimer
    interval: 240000
    repeat: true
    running: root.active && root.primary
    triggeredOnStart: true
    onTriggered: root.probeNetwork()
  }

  // ---------------------------------------------------------------- ticking

  // Seconds only matter in the last minute; the rest of the time a coarse tick
  // keeps the countdown honest without repainting the bar every second.
  Timer {
    interval: root.remainingMs > 0 && root.remainingMs <= 65000 ? 1000 : 10000
    repeat: true
    running: root.active
    onTriggered: root.now = Date.now()
  }

  onExpiredChanged: if (expired) root.stop()
  onActiveChanged: { syncInhibitor(); syncScreen() }
  onInhibitWhatChanged: syncInhibitor()
  onScreenWantedChanged: syncScreen()
  onPrimaryChanged: { syncInhibitor(); syncScreen() }

  // The config arrives after this component exists, so the first sync happens
  // when it lands rather than here.
  onReadyChanged: if (ready) { syncInhibitor(); syncScreen(); probeNetwork() }
}
