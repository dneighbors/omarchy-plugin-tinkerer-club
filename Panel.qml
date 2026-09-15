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
  property string lockinErrorText: ""
  property string lockinStatusHint: ""
  property string latestId: ""
  property string seenId: ""
  property int unreadCount: 0
  property bool pendingUnread: false
  property string panelView: "feed"
  property var notifications: []
  property var lockinCurrent: null
  property var lockinParticipants: []
  property string lockinServerNow: ""
  property bool lockinOnboarded: false
  property var lockinLastEnd: null
  property int lockinSkewMs: 0
  property int lockinFetchedAt: 0
  property int lockinRemainingMs: 0
  property string lockinTitleDraft: ""
  property string lockinWatchdogSessionId: ""
  property string lockinWatchdogRestartTitle: ""
  property bool lockinWatchdogPending: false
  property bool lockinWatchdogNotice: false
  property var lockinTodos: []
  property string lockinTodoDraft: ""
  readonly property bool lockinLive: lockinCurrent !== null
  readonly property bool lockinEarlyFinish: root.lockinLive
    && root.lockinElapsedMs(root.lockinCurrent ? root.lockinCurrent.startedAt : "") < (30 * 60 * 1000)
  readonly property bool hasNew: latestId !== "" && seenId !== "" && latestId !== seenId
  readonly property bool viewBusy: root.panelView === "notifications" ? listProc.running
    : (root.panelView === "lockin"
      ? (stateProc.running || startProc.running || finishProc.running || todosProc.running
        || todoAddProc.running || todoUpdateProc.running || todoDeleteProc.running)
      : feedProc.running)
  readonly property bool busy: statusProc.running || feedProc.running || unreadProc.running || listProc.running || markReadProc.running || markAllReadProc.running || stateProc.running || startProc.running || finishProc.running || todosProc.running || todoAddProc.running || todoUpdateProc.running || todoDeleteProc.running

  function syncViewMessages() {
    if (root.panelView === "notifications") {
      errorText = notificationsErrorText
      statusHint = notificationsStatusHint
    } else if (root.panelView === "lockin") {
      errorText = lockinErrorText
      statusHint = lockinStatusHint
    } else {
      errorText = feedErrorText
      statusHint = feedStatusHint
    }
  }

  function formatDuration(ms) {
    if (!isFinite(ms) || ms < 0) return "0:00"
    var totalSec = Math.floor(ms / 1000)
    var m = Math.floor(totalSec / 60)
    var s = totalSec % 60
    return m + ":" + (s < 10 ? "0" : "") + s
  }

  function lockinElapsedMs(startedAt) {
    if (!lockinCurrent || !startedAt) return 0
    var start = Date.parse(startedAt)
    if (!isFinite(start)) return 0
    return Math.max(0, Date.now() + lockinSkewMs - start)
  }

  function recomputeLockinRemainingMs() {
    if (!lockinCurrent || !lockinCurrent.expiresAt || lockinServerNow === "") {
      lockinRemainingMs = 0
      return
    }
    var expires = Date.parse(lockinCurrent.expiresAt)
    var server = Date.parse(lockinServerNow)
    if (!isFinite(expires) || !isFinite(server)) {
      lockinRemainingMs = 0
      return
    }
    var remaining = (expires - server) - (Date.now() - lockinFetchedAt)
    lockinRemainingMs = Math.max(0, remaining)
  }

  function lockinPageUrl() {
    var base = String(root.baseUrl).replace(/\/$/, "")
    return base + "/lock-in"
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

  function refreshLockinState() {
    if (!stateProc.running) {
      stateProc.command = root.cmd(["lockin", "state"])
      stateProc.running = true
    }
  }

  function refreshLockinTodos() {
    if (!todosProc.running) {
      todosProc.command = root.cmd(["lockin", "todos"])
      todosProc.running = true
    }
  }

  function lockinTodoAddArgs(title) {
    var trimmed = String(title === undefined || title === null ? "" : title).replace(/^\s+|\s+$/g, "")
    if (trimmed === "")
      return []
    if (trimmed.length > 200)
      trimmed = trimmed.slice(0, 200)
    return ["lockin", "todo-add"].concat(trimmed.split(/\s+/))
  }

  function lockinTodoAdd(title) {
    var args = root.lockinTodoAddArgs(title)
    if (args.length === 0 || todoAddProc.running || todoUpdateProc.running || todoDeleteProc.running)
      return
    todoAddProc.command = root.cmd(args)
    todoAddProc.running = true
  }

  function lockinTodoToggle(id, completed) {
    var trimmed = String(id === undefined || id === null ? "" : id).replace(/^\s+|\s+$/g, "")
    if (trimmed === "" || todoAddProc.running || todoUpdateProc.running || todoDeleteProc.running)
      return
    if (completed === true)
      todoUpdateProc.command = root.cmd(["lockin", "todo-update", trimmed, "false"])
    else
      todoUpdateProc.command = root.cmd(["lockin", "todo-done", trimmed])
    todoUpdateProc.running = true
  }

  function lockinTodoDelete(id) {
    var trimmed = String(id === undefined || id === null ? "" : id).replace(/^\s+|\s+$/g, "")
    if (trimmed === "" || todoAddProc.running || todoUpdateProc.running || todoDeleteProc.running)
      return
    todoDeleteProc.command = root.cmd(["lockin", "todo-delete", trimmed])
    todoDeleteProc.running = true
  }

  function lockinStartArgs(title) {
    var trimmed = String(title === undefined || title === null ? "" : title).replace(/^\s+|\s+$/g, "")
    if (trimmed === "")
      return ["lockin", "start"]
    if (trimmed.length > 160)
      trimmed = trimmed.slice(0, 160)
    return ["lockin", "start"].concat(trimmed.split(/\s+/))
  }

  function lockinStart(title) {
    if (root.lockinCurrent !== null || startProc.running || finishProc.running)
      return
    startProc.command = root.cmd(root.lockinStartArgs(title))
    startProc.running = true
  }

  function lockinFinish() {
    if (!root.lockinCurrent || !root.lockinCurrent.id || finishProc.running || startProc.running)
      return
    finishProc.command = root.cmd(["lockin", "finish", String(root.lockinCurrent.id)])
    finishProc.running = true
  }

  function checkLockinWatchdog() {
    if (!root.configured || !root.lockinCurrent || !root.lockinCurrent.id)
      return
    if (root.lockinWatchdogPending || finishProc.running || startProc.running)
      return
    if (root.lockinRemainingMs > 30000 || root.lockinRemainingMs <= 0)
      return
    if (root.lockinWatchdogSessionId === String(root.lockinCurrent.id))
      return
    root.lockinWatchdogSessionId = String(root.lockinCurrent.id)
    root.lockinWatchdogRestartTitle = String(root.lockinCurrent.title || "")
    root.lockinWatchdogPending = true
    finishProc.command = root.cmd(["lockin", "finish", String(root.lockinCurrent.id)])
    finishProc.running = true
  }

  function applyLockinFinish(data) {
    if (data && data.ok === true) {
      lockinErrorText = ""
      if (root.lockinWatchdogPending) {
        if (!startProc.running) {
          startProc.command = root.cmd(root.lockinStartArgs(root.lockinWatchdogRestartTitle))
          startProc.running = true
        }
      } else {
        root.refreshLockinState()
      }
      return
    }
    root.lockinWatchdogPending = false
    if (data && data.ok !== true && root.panelView === "lockin" && root.opened) {
      lockinErrorText = data.error || "Could not finish LockIn."
      lockinStatusHint = data.hint || ""
      errorText = lockinErrorText
      statusHint = lockinStatusHint
    }
  }

  function applyLockinStart(data) {
    if (data && data.ok === true) {
      lockinErrorText = ""
      if (root.lockinWatchdogPending) {
        root.lockinWatchdogNotice = true
        lockinStatusHint = "LockIn restarted automatically before the 60-minute cap."
        root.lockinWatchdogPending = false
        if (root.panelView === "lockin")
          statusHint = lockinStatusHint
      }
      root.refreshLockinState()
      return
    }
    root.lockinWatchdogPending = false
    if (data && data.ok !== true && root.panelView === "lockin" && root.opened) {
      lockinErrorText = data.error || "Could not start LockIn."
      lockinStatusHint = data.hint || ""
      errorText = lockinErrorText
      statusHint = lockinStatusHint
    }
  }

  function refresh() {
    if (root.opened && root.panelView === "notifications")
      root.refreshNotifications()
    else if (root.opened && root.panelView === "lockin") {
      root.refreshLockinState()
      root.refreshLockinTodos()
    } else
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

  function applyLockinTodos(data) {
    if (data && data.ok === true && Array.isArray(data.todos)) {
      lockinTodos = data.todos.filter(function(item) {
        return item && item.deleted !== true
      })
      if (root.panelView === "lockin") {
        lockinErrorText = ""
        if (lockinStatusHint === "")
          statusHint = ""
      }
      return
    }
    if (data && data.ok !== true && root.panelView === "lockin" && root.opened) {
      lockinErrorText = data.error || "Could not load LockIn checklist."
      lockinStatusHint = data.hint || ""
      errorText = lockinErrorText
      statusHint = lockinStatusHint
    }
  }

  function applyLockinTodoMutation(data) {
    if (data && data.ok === true) {
      lockinErrorText = ""
      root.refreshLockinTodos()
      return
    }
    if (data && data.ok !== true && root.panelView === "lockin" && root.opened) {
      lockinErrorText = data.error || "Could not update LockIn checklist."
      lockinStatusHint = data.hint || ""
      errorText = lockinErrorText
      statusHint = lockinStatusHint
    }
  }

  function applyLockinState(data) {
    if (data && data.ok === true) {
      lockinCurrent = data.current || null
      lockinParticipants = Array.isArray(data.participants) ? data.participants : []
      lockinServerNow = String(data.serverNow || "")
      lockinOnboarded = data.onboarded === true
      lockinLastEnd = data.lastEnd || null
      var serverStamp = Date.parse(lockinServerNow)
      lockinSkewMs = isFinite(serverStamp) ? serverStamp - Date.now() : 0
      lockinFetchedAt = Date.now()
      recomputeLockinRemainingMs()
      lockinErrorText = ""
      var keepWatchdogHint = root.lockinWatchdogNotice
      root.lockinWatchdogNotice = false
      if (!keepWatchdogHint)
        lockinStatusHint = ""
      if (root.panelView === "lockin") {
        errorText = ""
        statusHint = lockinStatusHint
      }
      return
    }
    if (data && data.ok !== true && root.panelView === "lockin" && root.opened) {
      lockinErrorText = data.error || "Could not load LockIn state."
      lockinStatusHint = data.hint || ""
      errorText = lockinErrorText
      statusHint = lockinStatusHint
    }
  }

  onPanelViewChanged: root.syncViewMessages()

  onOpenedChanged: {
    if (opened) {
      if (configured) refresh()
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

  Process {
    id: stateProc
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        root.applyLockinState(data)
      }
    }
  }

  Process {
    id: startProc
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        root.applyLockinStart(data)
      }
    }
  }

  Process {
    id: finishProc
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        root.applyLockinFinish(data)
      }
    }
  }

  Process {
    id: todosProc
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        root.applyLockinTodos(data)
      }
    }
  }

  Process {
    id: todoAddProc
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        if (data && data.ok === true)
          root.lockinTodoDraft = ""
        root.applyLockinTodoMutation(data)
      }
    }
  }

  Process {
    id: todoUpdateProc
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        root.applyLockinTodoMutation(data)
      }
    }
  }

  Process {
    id: todoDeleteProc
    stdout: StdioCollector {
      onStreamFinished: {
        var data
        try { data = JSON.parse(text) } catch (e) { return }
        root.applyLockinTodoMutation(data)
      }
    }
  }

  Timer {
    interval: 1000
    running: root.lockinCurrent !== null
    repeat: true
    onTriggered: {
      root.recomputeLockinRemainingMs()
      root.checkLockinWatchdog()
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
      if (root.configured && root.lockinCurrent !== null)
        root.refreshLockinState()
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

          WidgetButton {
            bar: root.bar
            text: "LockIn"
            active: root.panelView === "lockin"
            activeColor: Color.accent
            onPressed: function(buttonCode) {
              if (buttonCode === Qt.LeftButton) {
                root.panelView = "lockin"
                root.refreshLockinState()
                root.refreshLockinTodos()
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

        Column {
          width: parent.width
          spacing: Style.space(8)
          visible: root.panelView === "lockin"

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.lockinCurrent === null && root.configured

            Text {
              width: parent.width
              text: "Session title (optional)"
              color: root.mutedForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Rectangle {
              width: parent.width
              height: lockinTitleField.implicitHeight + Style.space(8)
              radius: Style.space(4)
              color: Style.hoverFillFor(root.contentForeground, Color.accent, Color.urgent)
              border.color: root.mutedForeground
              border.width: 1

              TextInput {
                id: lockinTitleField
                anchors.fill: parent
                anchors.margins: Style.space(4)
                text: root.lockinTitleDraft
                onTextChanged: root.lockinTitleDraft = text
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                maximumLength: 160
                selectByMouse: true
                clip: true
              }
            }

            WidgetButton {
              width: parent.width
              bar: root.bar
              text: "Start"
              enabled: !startProc.running && !finishProc.running
              onPressed: function(buttonCode) {
                if (buttonCode === Qt.LeftButton)
                  root.lockinStart(root.lockinTitleDraft)
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: root.lockinCurrent !== null

            Text {
              width: parent.width
              text: root.plain(root.lockinCurrent ? root.lockinCurrent.title || "LockIn" : "")
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              wrapMode: Text.WordWrap
            }

            RowLayout {
              width: parent.width
              spacing: Style.space(12)

              Text {
                text: "Elapsed " + root.formatDuration(root.lockinElapsedMs(root.lockinCurrent ? root.lockinCurrent.startedAt : ""))
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                text: root.formatDuration(root.lockinRemainingMs) + " left"
                color: Color.accent
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
            }

            Text {
              width: parent.width
              text: "60 min cap"
              color: root.mutedForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              width: parent.width
              visible: root.lockinEarlyFinish
              text: "Finishing before 30 minutes does not earn Sparkles. The reward window is 30\u201360 minutes."
              color: root.mutedForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            WidgetButton {
              width: parent.width
              bar: root.bar
              text: "Finish"
              enabled: !startProc.running && !finishProc.running
              onPressed: function(buttonCode) {
                if (buttonCode === Qt.LeftButton)
                  root.lockinFinish()
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.lockinCurrent !== null

            Text {
              width: parent.width
              text: "Locked in now \u00b7 " + root.lockinParticipants.length
              color: root.mutedForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Repeater {
              model: root.lockinParticipants

              delegate: Column {
                required property var modelData
                width: parent.width
                spacing: Style.space(2)

                Text {
                  width: parent.width
                  text: root.plain(modelData.name || "Tinkerer")
                  color: root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: root.plain(root.snippet(modelData.title || "", 60))
                  color: root.mutedForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width
                  text: root.formatDuration(root.lockinElapsedMs(modelData.startedAt)) + " elapsed"
                  color: root.mutedForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                }
              }
            }
          }

          Text {
            width: parent.width
            visible: root.lockinCurrent === null && root.configured && !root.viewBusy && root.errorText === ""
            text: "No LockIn session running."
            color: root.mutedForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            width: parent.width
            visible: root.lockinCurrent === null && root.lockinLastEnd && root.lockinLastEnd.automaticallyEnded === true && root.errorText === ""
            text: "Your last session ended at the 60-minute cap."
            color: root.mutedForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            visible: !root.lockinOnboarded && root.errorText === ""
            text: "Set up LockIn on the web to join co-working sessions."
            color: root.mutedForeground
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          WidgetButton {
            width: parent.width
            visible: !root.lockinOnboarded
            bar: root.bar
            text: "Open LockIn on web"
            onPressed: function(buttonCode) {
              if (buttonCode === Qt.LeftButton)
                root.openUrl(root.lockinPageUrl())
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: root.configured

            Text {
              width: parent.width
              text: "Checklist"
              color: root.mutedForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }

            Rectangle {
              width: parent.width
              height: lockinTodoField.implicitHeight + Style.space(8)
              radius: Style.space(4)
              color: Style.hoverFillFor(root.contentForeground, Color.accent, Color.urgent)
              border.color: root.mutedForeground
              border.width: 1

              TextInput {
                id: lockinTodoField
                anchors.fill: parent
                anchors.margins: Style.space(4)
                text: root.lockinTodoDraft
                onTextChanged: root.lockinTodoDraft = text
                color: root.contentForeground
                font.family: root.contentFontFamily
                font.pixelSize: Style.font.body
                maximumLength: 200
                selectByMouse: true
                clip: true
              }
            }

            WidgetButton {
              width: parent.width
              bar: root.bar
              text: "Add todo"
              enabled: !todoAddProc.running && !todoUpdateProc.running && !todoDeleteProc.running
              onPressed: function(buttonCode) {
                if (buttonCode === Qt.LeftButton)
                  root.lockinTodoAdd(root.lockinTodoDraft)
              }
            }

            Repeater {
              model: root.lockinTodos

              delegate: RowLayout {
                required property var modelData
                width: parent.width
                spacing: Style.space(6)

                WidgetButton {
                  bar: root.bar
                  text: modelData.completed === true ? "\u2611" : "\u2610"
                  enabled: !todoAddProc.running && !todoUpdateProc.running && !todoDeleteProc.running
                  onPressed: function(buttonCode) {
                    if (buttonCode === Qt.LeftButton)
                      root.lockinTodoToggle(modelData.id, modelData.completed === true)
                  }
                }

                Text {
                  Layout.fillWidth: true
                  text: root.plain(modelData.title || "")
                  color: modelData.completed === true ? root.mutedForeground : root.contentForeground
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.body
                  font.strikeout: modelData.completed === true
                  wrapMode: Text.WordWrap
                }

                WidgetButton {
                  bar: root.bar
                  text: "Delete"
                  enabled: !todoAddProc.running && !todoUpdateProc.running && !todoDeleteProc.running
                  onPressed: function(buttonCode) {
                    if (buttonCode === Qt.LeftButton)
                      root.lockinTodoDelete(modelData.id)
                  }
                }
              }
            }

            Text {
              width: parent.width
              visible: root.lockinTodos.length === 0 && !todosProc.running && root.errorText === ""
              text: "No checklist items yet."
              color: root.mutedForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
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
