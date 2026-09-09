import QtQuick
import qs.Commons
import qs.Ui

// Toggle row with an explicit green/gray switch. The shell's Toggle takes its
// switch colours from theme tokens, which pin them whatever foreground says.
BorderSurface {
  id: root

  property string label: ""
  property string description: ""
  property bool checked: false
  property color onColor: "#3fb950"
  property color offColor: Color.muted
  property color textColor: Color.popups.text
  property bool rounded: Style.cornerRadius > 0

  readonly property color stateColor: checked ? onColor : offColor

  signal clicked()

  activeFocusOnTab: true
  Keys.onReturnPressed: root.clicked()
  Keys.onEnterPressed: root.clicked()
  Keys.onSpacePressed: root.clicked()

  implicitHeight: Math.max(54, content.implicitHeight + Style.spacing.huge)
  implicitWidth: Style.space(240)
  radius: Style.cornerRadius

  readonly property bool hot: mouse.containsMouse

  color: Util.alpha(stateColor, hot || activeFocus ? 0.14 : 0.06)
  borderSpec: Border.controlSpec(activeFocus ? "focus" : (hot ? "hover-cursor" : "normal"),
                                 stateColor, stateColor)

  Behavior on color { ColorAnimation { duration: 120 } }

  Row {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: root.borderLeft + Style.spacing.rowPaddingX
    anchors.rightMargin: root.borderRight + Style.spacing.rowPaddingX
    spacing: Style.spacing.rowPaddingX

    Column {
      width: parent.width - track.width - parent.spacing
      spacing: Style.spacing.xs
      anchors.verticalCenter: parent.verticalCenter

      Text {
        textFormat: Text.PlainText
        text: root.label
        color: root.stateColor
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        textFormat: Text.PlainText
        visible: root.description !== ""
        text: root.description
        color: root.textColor
        opacity: 0.72
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        width: parent.width
      }
    }

    Item {
      id: track
      width: trackRect.width + Style.space(12)
      height: trackRect.height + Style.space(12)
      anchors.verticalCenter: parent.verticalCenter

      Rectangle {
        id: trackRect
        anchors.centerIn: parent
        width: Math.round(height * 1.9)
        height: Math.max(22, Math.round(Style.spacing.controlHeight * 0.55))
        radius: root.rounded ? height / 2 : 0
        color: Util.alpha(root.stateColor, root.checked ? 0.30 : 0.12)
        border.width: 1
        border.color: Util.alpha(root.stateColor, root.checked ? 0.95 : 0.45)

        Behavior on color { ColorAnimation { duration: 120 } }

        Rectangle {
          height: Math.max(6, Math.round(parent.height * 0.72))
          width: height
          radius: root.rounded ? height / 2 : 0
          x: root.checked ? parent.width - width - inset : inset
          anchors.verticalCenter: parent.verticalCenter
          color: root.stateColor

          readonly property int inset: Math.max(1, Math.round((parent.height - height) / 2))

          Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
          Behavior on color { ColorAnimation { duration: 120 } }
        }
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
