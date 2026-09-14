pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Tinkerer Club feed popup. The member key stays in a file; bin/tinkerer
// is the only thing that reads it.
Panel {
  id: root
  moduleName: "dneighbors.tinkerer-club"
  ipcTarget: "dneighbors.tinkerer-club"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property string script:
    Qt.resolvedUrl("bin/tinkerer").toString().replace(/^file:\/\//, "")

  readonly property string apiKeyFile: setting("apiKeyFile", "")
  readonly property string baseUrl: setting("baseUrl", "https://app.tinkerer.club")
  readonly property int feedLimit: setting("feedLimit", 20)
  readonly property int panelWidth: setting("panelWidth", 380)
  readonly property int refreshMinutes: setting("refreshMinutes", 5)

  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color mutedForeground: Color.muted
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property int listMaxHeight: Style.space(420)

  property var posts: []
  property bool configured: false
  property string statusHint: ""
  property string errorText: ""
  property string feedErrorText: ""
  property string feedStatusHint: ""
  property string notificationsErrorText: ""
  property string notificationsStatusHint: ""
  property string latestId: ""
  property string seenId: ""
  property int unreadCount: 0
  property bool pendingUnread: false
  property string panelView: "feed"
  property var notifications: []
  readonly property bool hasNew: latestId !== "" && seenId !== "" && latestId !== seenId
  readonly property bool viewBusy: root.panelView === "notifications" ? listProc.running : feedProc.running
  readonly property bool busy: statusProc.running || feedProc.running || unreadProc.running || listProc.running || markReadProc.running || markAllReadProc.running

  function syncViewMessages() {
    if (root.panelView === "notifications") {
      errorText = notificationsErrorText
      statusHint = notificationsStatusHint
    } else {
      errorText = feedErrorText
      statusHint = feedStatusHint
    }
  }

  function cmd(args) {
    var base = [root.script, "--base-url", String(root.baseUrl), "--limit", String(root.feedLimit)]
    if (root.apiKeyFile !== "")
      base = base.concat(["--key-file", String(root.apiKeyFile)])
    return base.concat(args)
  }

  function plain(s) {
    return String(s === undefined || s === null ? "" : s).replace(/[<>]/g, "")
  }

  function snippet(s, maxLen) {
    var text = String(s === undefined || s === null ? "" : s).replace(/\s+/g, " ").trim()
    if (text.length <= maxLen) return text
    return text.slice(0, maxLen - 1) + "\u2026"
  }

  function relativeTime(value) {
    var stamp = Date.parse(value)
    if (!isFinite(stamp)) return ""
    var seconds = Math.round((Date.now() - stamp) / 1000)
    if (seconds < 60) return "just now"
    var minutes = Math.round(seconds / 60)
    if (minutes < 60) return minutes + "m"
    var hours = Math.round(minutes / 60)
    if (hours < 24) return hours + "h"
    return Math.round(hours / 24) + "d"
  }

  function markSeen() {
    if (latestId !== "") seenId = latestId
  }

  function refreshFeed() {
    if (!feedProc.running) {
      feedProc.command = root.cmd(["feed"])
      feedProc.running = true
    }
  }

  function refreshNotifications() {
    if (!root.opened)
      return
    if (!listProc.running) {
      listProc.command = root.cmd(["notifications", "list"])
      listProc.running = true
    }
  }

  function refresh() {
    if (root.opened && root.panelView === "notifications")
      root.refreshNotifications()
    else
      root.refreshFeed()
  }

  function refreshUnread() {
    if (unreadProc.running) {
      pendingUnread = true
      return
    }
    unreadProc.command = root.cmd(["notifications", "unread"])
    unreadProc.running = true
  }

  function checkStatus() {
    if (!statusProc.running) {
      statusProc.command = root.cmd(["status"])
      statusProc.running = true
    }
  }

  function openUrl(url) {
    if (!url) return
    browserProc.command = ["xdg-open", String(url)]
    browserProc.running = true
  }

  function markRead(id) {
    var trimmed = String(id === undefined || id === null ? "" : id).replace(/^\s+|\s+$/g, "")
    if (trimmed === "")
      return
    if (!root.opened || root.panelView !== "notifications")
      return
    if (markReadProc.running)
      return
    markReadProc.command = root.cmd(["notifications", "mark-read", trimmed])
    markReadProc.running = true
  }

  function markAllRead() {
    if (!root.opened || root.panelView !== "notifications")
      return
    if (markAllReadProc.running)
      return
    markAllReadProc.command = root.cmd(["notifications", "mark-all-read"])
    markAllReadProc.running = true
  }

  function applyMark(data) {
    if (data && data.ok === true) {
      if (root.panelView === "notifications") {
        notificationsErrorText = ""
        notificationsStatusHint = ""
        errorText = ""
        statusHint = ""
      }
      root.refreshUnread()
      return
    }
    if (data && data.ok !== true && root.panelView === "notifications" && root.opened) {
      notificationsErrorText = data.error || "Could not mark notifications read."
      notificationsStatusHint = data.hint || ""
      errorText = notificationsErrorText
      statusHint = notificationsStatusHint
    }
  }

  function applyStatus(data) {
    configured = data.configured === true
    statusHint = data.hint || ""
    feedStatusHint = statusHint
    notificationsStatusHint = statusHint
    if (data.configured !== true) {
      errorText = data.error || "Add your Tinkerer Club API key."
      feedErrorText = errorText
      notificationsErrorText = errorText
    } else if (errorText === "Add your Tinkerer Club API key.") {
      errorText = ""
      if (feedErrorText === "Add your Tinkerer Club API key.")
        feedErrorText = ""
      if (notificationsErrorText === "Add your Tinkerer Club API key.")
        notificationsErrorText = ""
    }
    if (root.configured && !root.opened)
      root.refreshUnread()
  }

  function applyFeed(data) {
    if (data.ok !== true) {
      feedErrorText = data.error || "Could not load the feed."
      feedStatusHint = data.hint || ""
      if (root.panelView === "feed") {
        errorText = feedErrorText
        statusHint = feedStatusHint
      }
      configured = data.error !== "Add your Tinkerer Club API key." ? configured : false
      return
    }
    configured = true
    feedErrorText = ""
    feedStatusHint = ""
    if (root.panelView === "feed") {
      errorText = ""
      statusHint = ""
    }
    posts = data.posts || []
    if (posts.length)
      latestId = String(posts[0].id || "")
    if (root.opened)
      markSeen()
    if (root.configured && root.opened)
      root.refreshUnread()
  }

  function applyUnread(data) {
    if (data && data.ok === true && typeof data.count === "number" && isFinite(data.count) && data.count >= 0)
      unreadCount = Math.floor(data.count)
    if (pendingUnread) {
      pendingUnread = false
      root.refreshUnread()
    }
  }

  function applyNotifications(data) {
    if (data && data.ok === true && Array.isArray(data.notifications)) {
      root.notifications = data.notifications
      notificationsErrorText = ""
      notificationsStatusHint = ""
      if (root.panelView === "notifications") {
        errorText = ""
        statusHint = ""
      }
      return
    }
    if (data && data.ok !== true && root.opened) {
      notificationsErrorText = data.error || "Could not load notifications."
      notificationsStatusHint = data.hint || ""
      if (root.panelView === "notifications") {
        errorText = notificationsErrorText
        statusHint = notificationsStatusHint
      }
    }
  }

  onPanelViewChanged: root.syncViewMessages()

  onOpenedChanged: {
    if (opened) {
      if (configured) refreshFeed()
      else checkStatus()
      markSeen()
    } else {
      panelView = "feed"
    }
  }

  Process {
    id: statusProc
    command: root.cmd(["status"])
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        root.applyStatus(data)
        if (root.configured && root.opened) root.refreshFeed()
      }
    }
  }

  Process {
    id: feedProc
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        root.applyFeed(data)
      }
    }
  }

  Process { id: browserProc }

  Process {
    id: unreadProc
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        root.applyUnread(data)
      }
    }
  }

  Process {
    id: listProc
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        root.applyNotifications(data)
      }
    }
  }

  Process {
    id: markReadProc
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        root.applyMark(data)
      }
    }
  }

  Process {
    id: markAllReadProc
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        root.applyMark(data)
      }
    }
  }

  Timer {
    interval: Math.max(1, root.refreshMinutes) * 60000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (root.opened) root.refreshFeed()
      else root.checkStatus()
      if (root.configured && !root.opened && !feedProc.running) {
        feedProc.command = root.cmd(["feed"])
        feedProc.running = true
      }
      if (root.configured && !root.opened)
        root.refreshUnread()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(root.panelWidth))
    contentHeight: panel.fittedContentHeight(body.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
          root.bar.switchPanelFrom(root.barIdentity, direction)
      }

      Column {
        id: body
        width: parent.width
        spacing: Style.space(10)

        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          Text {
            text: "Tinkerer Club"
            color: root.contentForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
          }

          WidgetButton {
            bar: root.bar
            text: root.viewBusy ? "\u2026" : "Refresh"
            enabled: !root.viewBusy
            onPressed: function(buttonCode) {
              if (buttonCode === Qt.LeftButton) root.refresh()
            }
          }
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(8)

          WidgetButton {
            bar: root.bar
            text: "Feed"
            active: root.panelView === "feed"
            activeColor: Color.accent
            onPressed: function(buttonCode) {
              if (buttonCode === Qt.LeftButton)
                root.panelView = "feed"
            }
          }

          WidgetButton {
            bar: root.bar
            text: "Notifications"
            active: root.panelView === "notifications"
            activeColor: Color.accent
            onPressed: function(buttonCode) {
              if (buttonCode === Qt.LeftButton) {
                root.panelView = "notifications"
                root.refreshNotifications()
              }
            }
          }

          Item { Layout.fillWidth: true }
        }

        RowLayout {
          width: parent.width
          spacing: Style.space(8)
          visible: root.panelView === "notifications" && root.unreadCount > 0

          WidgetButton {
            bar: root.bar
            text: "Mark all read"
            enabled: !markAllReadProc.running
            onPressed: function(buttonCode) {
              if (buttonCode === Qt.LeftButton)
                root.markAllRead()
            }
          }

          Item { Layout.fillWidth: true }
        }

        Text {
          width: parent.width
          visible: root.errorText !== ""
          text: root.plain(root.errorText)
          color: Color.urgent
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          visible: root.statusHint !== ""
          text: root.plain(root.statusHint)
          color: root.mutedForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Flickable {
          id: feedFlick
          width: parent.width
          height: Math.min(feedColumn.implicitHeight, root.listMaxHeight)
          contentWidth: width
          contentHeight: feedColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          visible: root.panelView === "feed" && root.posts.length > 0

          Column {
            id: feedColumn
            width: feedFlick.width
            spacing: Style.space(6)

            Repeater {
              model: root.posts

              delegate: Item {
                required property var modelData
                width: feedColumn.width
                height: row.implicitHeight + Style.space(8)

                Rectangle {
                  anchors.fill: parent
                  radius: Style.space(4)
                  color: rowMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Color.accent, Color.urgent)
                    : "transparent"
                }

                MouseArea {
                  id: rowMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openUrl(modelData.url)
                }

                Column {
                  id: row
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.margins: Style.space(8)
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    text: root.plain(modelData.author || "Tinkerer")
                    color: root.mutedForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: root.plain(root.snippet(modelData.title || modelData.content || "Untitled", 90))
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    text: root.plain([
                      root.relativeTime(modelData.publishedAt),
                      modelData.commentCount ? (modelData.commentCount + " comments") : "",
                      modelData.reactionCount ? (modelData.reactionCount + " reactions") : ""
                    ].filter(function(part) { return part }).join(" \u00b7 "))
                    color: root.mutedForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }
        }

        Flickable {
          id: notificationsFlick
          width: parent.width
          height: Math.min(notificationsColumn.implicitHeight, root.listMaxHeight)
          contentWidth: width
          contentHeight: notificationsColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          visible: root.panelView === "notifications" && root.notifications.length > 0

          Column {
            id: notificationsColumn
            width: notificationsFlick.width
            spacing: Style.space(6)

            Repeater {
              model: root.notifications

              delegate: Item {
                required property var modelData
                width: notificationsColumn.width
                height: Math.max(noteRow.implicitHeight, markReadBtn.implicitHeight) + Style.space(8)

                Rectangle {
                  anchors.fill: parent
                  radius: Style.space(4)
                  color: noteMouse.containsMouse
                    ? Style.hoverFillFor(root.contentForeground, Color.accent, Color.urgent)
                    : "transparent"
                }

                MouseArea {
                  id: noteMouse
                  anchors.left: parent.left
                  anchors.top: parent.top
                  anchors.bottom: parent.bottom
                  anchors.right: markReadBtn.left
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openUrl(modelData.url)
                }

                WidgetButton {
                  id: markReadBtn
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.rightMargin: Style.space(8)
                  bar: root.bar
                  text: "Mark read"
                  enabled: !markReadProc.running
                  onPressed: function(buttonCode) {
                    if (buttonCode === Qt.LeftButton)
                      root.markRead(String(modelData.id || ""))
                  }
                }

                Column {
                  id: noteRow
                  anchors.left: parent.left
                  anchors.right: markReadBtn.left
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: root.plain(modelData.sender || "Tinkerer")
                    color: root.mutedForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: {
                      var title = root.plain(root.snippet(modelData.title, 90))
                      return title !== "" ? title : "Notification"
                    }
                    color: root.contentForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                  }

                  Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: root.plain(root.relativeTime(modelData.createdAt))
                    color: root.mutedForeground
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    elide: Text.ElideRight
                  }
                }
              }
            }
          }
        }

        Text {
          width: parent.width
          visible: root.panelView === "feed" && root.configured && root.posts.length === 0 && !root.viewBusy && root.errorText === ""
          text: "No posts yet."
          color: root.mutedForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width
          visible: root.panelView === "notifications" && root.configured && root.notifications.length === 0 && !root.viewBusy && root.errorText === ""
          text: "No notifications yet."
          color: root.mutedForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.body
        }

        WidgetButton {
          width: parent.width
          bar: root.bar
          text: "Open Tinkerer Club"
          onPressed: function(buttonCode) {
            if (buttonCode === Qt.LeftButton) root.openUrl(root.baseUrl)
          }
        }
      }
    }
  }
}
