import QtQuick
import QtQuick.Window
import Quickshell
import qs.Commons
import qs.Ui
import "Format.js" as Format

// Bar entry for Insomnia: one glyph that toggles the keep-awake session on the
// left button and opens the settings popup on the right.
BarWidget {
  id: root
  moduleName: "kairos.insomnia"

  readonly property string pluginDir: {
    var url = String(Qt.resolvedUrl("."))
    if (url.indexOf("file://") === 0) url = url.substring(7)
    while (url.length > 1 && url.charAt(url.length - 1) === "/") url = url.substring(0, url.length - 1)
    return decodeURIComponent(url)
  }

  readonly property string home: Quickshell.env("HOME") || ""

  function configPath() {
    var base = Quickshell.env("XDG_CONFIG_HOME") || ""
    if (base === "") base = home === "" ? "" : home + "/.config"
    return base === "" ? "" : base + "/omarchy/kairos-insomnia.json"
  }

  // A bar widget is instantiated once per monitor. Only the instance on the
  // first screen runs processes; an unresolved screen counts as first.
  readonly property bool primary: {
    var win = Window.window
    var screens = Quickshell.screens
    if (!win || !win.screen || !screens || screens.length === 0) return true
    return String(win.screen.name) === String(screens[0].name)
  }

  Config {
    id: cfg
    path: root.configPath()
  }

  Session {
    id: session
    cfg: cfg
    pluginDir: root.pluginDir
    primary: root.primary
  }

  readonly property string glyph: session.active ? "󰒳" : "󰒲"

  readonly property string labelText: {
    if (!session.active) return glyph
    if (session.inhibitorFailed) return glyph + " !"
    if (!session.timed) return glyph
    return glyph + " " + Format.remaining(session.remainingMs)
  }

  readonly property string tooltip: {
    if (!session.ready) return "Insomnia"
    if (!session.active) return "Insomnia — off. Click to keep this machine awake."
    if (session.inhibitorFailed) return "Insomnia — on, but logind refused the sleep inhibitor. Open the panel for details."
    var parts = []
    parts.push(session.timed
      ? "Insomnia — awake for another " + Format.remaining(session.remainingMs)
      : "Insomnia — awake, no time limit")
    parts.push("Blocking suspend and idle" + (session.inhibitLid ? ", lid close ignored" : ""))
    if (session.keepScreenOn) parts.push(session.screenHeld ? "Screen stays on" : "Screen lock held elsewhere")
    if (session.keepalive && session.netGateway !== "")
      parts.push("Gateway " + session.netGateway + " " + (session.netPing === "ok" ? "reachable" : session.netPing))
    return parts.join(" · ")
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("session" in target) target.session = session
    if ("manageIpc" in target) target.manageIpc = root.primary
  }

  function togglePanel() { if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle() }
  function open() { if (panelLoader.item && panelLoader.item.open) panelLoader.item.open() }
  function close() { if (panelLoader.item && panelLoader.item.close) panelLoader.item.close() }
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  implicitWidth: content.implicitWidth
  implicitHeight: content.implicitHeight
  visible: true

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  Row {
    id: content
    spacing: 0

    WidgetButton {
      id: button
      bar: root.bar
      text: Format.barSafe(root.labelText, 24)
      tooltipText: Format.barSafe(root.tooltip, 240)
      active: session.active
      hasVisualContent: true
      labelVisible: true
      onPressed: function (mouseButton) {
        if (mouseButton === Qt.RightButton) root.togglePanel()
        else session.toggle()
      }
    }
  }
}
