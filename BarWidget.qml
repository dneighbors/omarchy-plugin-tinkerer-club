import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "dneighbors.tinkerer-club"

  readonly property bool opened: panelItem ? panelItem.opened === true : false
  readonly property bool popoutSwitchClosing: panelItem ? panelItem.popoutSwitchClosing === true : false
  readonly property bool hasNew: panelItem ? panelItem.hasNew === true : false
  readonly property int unreadCount: {
    if (!panelItem || panelItem.unreadCount === undefined)
      return 0
    var n = Number(panelItem.unreadCount)
    return isNaN(n) ? 0 : n
  }

  property var panelItem: null

  function open() { if (panelItem) panelItem.open() }
  function close() { if (panelItem) panelItem.close() }
  function togglePanel() { if (panelItem) panelItem.toggle() }
  function closeForPopoutSwitch() { if (panelItem) panelItem.closeForPopoutSwitch() }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    panelItem = target
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "dneighbors.tinkerer-club"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
    function refresh(): void { if (root.panelItem && root.panelItem.refresh) root.panelItem.refresh() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Lobster. Private-use-safe emoji escapes so the source survives patches.
    text: "\ud83e\udd9e"
    tooltipText: root.opened
      ? "Close Tinkerer Club"
      : (root.unreadCount > 0 ? ("Tinkerer Club · " + root.unreadCount + " unread") : "Tinkerer Club")

    Rectangle {
      id: unreadBadge
      visible: root.unreadCount > 0 && !root.opened
      anchors.right: parent.right
      anchors.rightMargin: Style.space(1)
      anchors.top: parent.top
      anchors.topMargin: Style.space(3)
      width: Math.max(countText.implicitWidth + Style.space(6), Style.space(12))
      height: Style.space(12)
      radius: height / 2
      color: Color.accent

      Text {
        id: countText
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: root.unreadCount > 99 ? "99+" : String(root.unreadCount)
        font.family: Style.font.family
        font.pixelSize: Math.max(8, Style.font.caption - Style.space(3))
        font.bold: true
        color: Color.background
      }
    }

    Rectangle {
      visible: root.hasNew && !root.opened && root.unreadCount <= 0
      width: 6
      height: 6
      radius: 3
      color: Color.accent
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: 1
      anchors.topMargin: 1
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.togglePanel()
    }
  }
}
