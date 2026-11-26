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
  readonly property bool lockinLive: panelItem ? panelItem.lockinLive === true : false
  readonly property int lockinRemainingMs: {
    if (!panelItem || panelItem.lockinRemainingMs === undefined)
      return 0
    var n = Number(panelItem.lockinRemainingMs)
    return isNaN(n) ? 0 : n
  }
  readonly property bool liveNow: panelItem ? panelItem.liveNow === true : false
  readonly property string liveTitle: panelItem && panelItem.liveTitle ? String(panelItem.liveTitle) : ""
  readonly property bool showLiveCue: liveNow && !opened
  readonly property bool showSessionCue: lockinLive && !opened && unreadCount <= 0
  readonly property bool coworkingSoon: panelItem ? panelItem.coworkingSoon === true : false
  readonly property string coworkingCueText: panelItem && panelItem.coworkingCueText ? String(panelItem.coworkingCueText) : ""
  // Below the live dot, the unread badge and the LockIn countdown; above the
  // new-activity dot.
  readonly property bool showCoworkingCue: coworkingSoon && !opened && !liveNow && unreadCount <= 0 && !lockinLive

  property var panelItem: null

  function formatDuration(ms) {
    if (!isFinite(ms) || ms < 0)
      return "0:00"
    var totalSec = Math.floor(ms / 1000)
    var m = Math.floor(totalSec / 60)
    var s = totalSec % 60
    return m + ":" + (s < 10 ? "0" : "") + s
  }

  function open() { if (panelItem) panelItem.open() }
  function close() { if (panelItem) panelItem.close() }
  function togglePanel() { if (panelItem) panelItem.toggle() }
  function press() {
    if (showCoworkingCue && panelItem && panelItem.openCoworkingTab) panelItem.openCoworkingTab()
    else togglePanel()
  }
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

  // The shell caches a QML file by its URL for as long as it runs, so after
  // `omarchy plugin update` a plain "Panel.qml" would keep serving the old
  // panel. Keying the URL by the file's contents makes a rebuilt widget load
  // the panel that is on disk now.
  property string panelSource: ""

  function contentStamp(text) {
    var h = 5381
    for (var i = 0; i < text.length; i++)
      h = ((h * 33) ^ text.charCodeAt(i)) >>> 0
    return h.toString(16)
  }

  FileView {
    id: panelFile
    path: Qt.resolvedUrl("Panel.qml").toString().replace(/^file:\/\//, "")
    blockLoading: true
    printErrors: false
    onLoaded: root.panelSource =
      Qt.resolvedUrl("Panel.qml") + "?v=" + root.contentStamp(panelFile.text())
    onLoadFailed: root.panelSource = Qt.resolvedUrl("Panel.qml")
  }

  Loader {
    id: panelLoader
    active: root.panelSource !== ""
    source: root.panelSource
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
      : root.showLiveCue
        ? ("Tinkerer Club · Live now: " + root.liveTitle)
        : (root.unreadCount > 0
            ? ("Tinkerer Club · " + root.unreadCount + " unread")
            : (root.showSessionCue
                ? ("Tinkerer Club · LockIn " + root.formatDuration(root.lockinRemainingMs) + " remaining")
                : (root.showCoworkingCue
                    ? ("Tinkerer Club · Coworking: " + root.coworkingCueText)
                    : "Tinkerer Club")))

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
      id: sessionCue
      visible: root.showSessionCue
      anchors.left: parent.left
      anchors.leftMargin: Style.space(1)
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.space(1)
      height: Style.space(10)
      width: sessionCueText.implicitWidth + Style.space(4)
      radius: height / 2
      color: Color.background
      border.color: Color.accent
      border.width: 1

      Text {
        id: sessionCueText
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: root.formatDuration(root.lockinRemainingMs)
        font.family: Style.font.family
        font.pixelSize: Math.max(8, Style.font.caption - Style.space(3))
        font.bold: true
        color: Color.accent
      }
    }

    Rectangle {
      id: liveCue
      visible: root.showLiveCue
      width: 6
      height: 6
      radius: 3
      color: Color.urgent
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.leftMargin: 1
      anchors.topMargin: 1
    }

    // Coworking cue: a ring, so it does not read as the new-activity dot.
    Rectangle {
      id: coworkingCue
      visible: root.showCoworkingCue
      width: 8
      height: 8
      radius: 4
      color: Color.background
      border.color: Color.accent
      border.width: 2
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.rightMargin: 1
      anchors.bottomMargin: 1
    }

    Rectangle {
      visible: root.hasNew && !root.opened && root.unreadCount <= 0 && !root.lockinLive && !root.showCoworkingCue
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
      if (buttonCode === Qt.LeftButton) root.press()
    }
  }
}
