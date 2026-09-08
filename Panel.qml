import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Ui
import "Format.js" as Format

// Settings popup for Insomnia. Every control writes through the session, which
// owns the config file the bar widget reads back.
Panel {
  id: root
  moduleName: "kairos.insomnia-panel"
  ipcTarget: "kairos.insomnia"

  property var anchorItem: null
  property var hostWidget: null
  property var session: null
  readonly property var barIdentity: hostWidget || root

  readonly property bool live: session !== null && session.ready

  function openFromHotkey() { root.open() }

  onOpenedChanged: if (opened && session) session.probeNetwork()

  readonly property string statusLine: {
    if (!live) return "Loading…"
    if (!session.active) return "Sleeping normally"
    if (session.inhibitorFailed) return "Inhibitor refused by logind"
    return session.timed
      ? "Awake — " + Format.remaining(session.remainingMs) + " remaining"
      : "Awake — no time limit"
  }

  readonly property string networkLine: {
    if (!live) return ""
    if (session.netGateway === "") return "No default route found."
    var bits = []
    if (session.netIface !== "") bits.push(session.netIface)
    bits.push("gateway " + session.netGateway)
    bits.push("Wi-Fi power save " + session.netPowersave)
    if (session.netPing === "ok") bits.push("last keepalive reached it")
    else if (session.netPing === "fail") bits.push("last keepalive got no reply")
    return bits.join(" · ")
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(760))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: contentColumn
          width: parent.width
          spacing: Style.space(14)

          Text {
            width: parent.width
            text: "Insomnia"
            textFormat: Text.PlainText
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            renderType: Text.NativeRendering
          }

          Text {
            width: parent.width
            text: root.statusLine
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: root.live && root.session.active ? Color.accent : Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            renderType: Text.NativeRendering
          }

          // ------------------------------------------------------- session

          PanelSectionHeader { text: "Session"; foreground: Color.popups.text }

          Toggle {
            width: parent.width
            label: "Keep this machine awake"
            description: "Holds a logind block inhibitor on sleep and idle, so suspend cannot interrupt a running agent."
            checked: root.live && root.session.active
            onClicked: if (root.live) root.session.toggle()
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Text {
              text: "Duration — picking one while a session runs restarts the clock"
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              color: Color.muted
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              renderType: Text.NativeRendering
            }

            ButtonGroup {
              options: Format.durationOptions()
              value: root.live ? root.session.durationKey : "1h"
              onChanged: function (v) { if (root.live) root.session.setDuration(v) }
            }
          }

          // ---------------------------------------------------- what stays

          PanelSectionHeader { text: "What stays awake"; foreground: Color.popups.text }

          Toggle {
            width: parent.width
            label: "Ignore the lid closing"
            description: "Adds handle-lid-switch to the inhibitor. A closed laptop that never suspends can get very hot in a bag — leave this off unless the machine is on a desk."
            checked: root.live && root.session.inhibitLid
            onClicked: if (root.live) root.session.setFlag("inhibitLid", !root.session.inhibitLid)
          }

          Toggle {
            width: parent.width
            label: "Keep the screen on"
            description: "Holds omarchy's stay-awake indicator, which suppresses the screensaver and the idle lock. Agent sessions do not need this — the lock does not stop them."
            checked: root.live && root.session.keepScreenOn
            onClicked: if (root.live) root.session.setFlag("keepScreenOn", !root.session.keepScreenOn)
          }

          Text {
            width: parent.width
            visible: root.live && root.session.keepScreenOn && root.session.screenOwner === "other"
            text: "Stay-awake is already held outside Insomnia, so this is left alone. Run `omarchy toggle idle` to clear it."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }

          // ------------------------------------------------------- network

          PanelSectionHeader { text: "Network"; foreground: Color.popups.text }

          Toggle {
            width: parent.width
            label: "Ping the gateway every 4 min"
            description: "Blocking suspend already keeps the link up. This only helps against an access point that drops clients it has not heard from."
            checked: root.live && root.session.keepalive
            onClicked: if (root.live) root.session.setFlag("keepalive", !root.session.keepalive)
          }

          Text {
            width: parent.width
            text: root.networkLine
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }

          Text {
            width: parent.width
            visible: root.live && root.session.netPowersave === "on"
            text: "Wi-Fi power save is on, which can add latency spikes on an idle link. Turn it off system-wide with a NetworkManager drop-in: wifi.powersave = 2."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }

          Text {
            width: parent.width
            visible: root.live && root.session.inhibitorFailed
            text: "logind did not grant the block inhibitor. Check `systemd-inhibit --list` and the org.freedesktop.login1.inhibit-block-sleep polkit rule."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }

          Text {
            width: parent.width
            text: "Settings live in ~/.config/omarchy/kairos-insomnia.json and take effect immediately."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            color: Color.muted
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            renderType: Text.NativeRendering
          }
        }
      }
    }
  }
}
