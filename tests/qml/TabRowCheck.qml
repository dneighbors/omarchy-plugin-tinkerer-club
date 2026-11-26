import QtQuick
import Quickshell
import qs.Commons
import "plugin" as Plugin

// Lays the real tab row out with the six shipped tabs at the default and the smallest panel
// width, and prints one line per case for tests/tab-row.sh to assert on.
ShellRoot {
  id: check

  readonly property var widths: [380, 300]
  readonly property var sixTabs: [
    { view: "feed", label: "Feed", name: "Feed: recent posts" },
    { view: "notifications", label: "Notifications", name: "Notifications: your unread and recent" },
    { view: "events", label: "Events", name: "Events: upcoming club events" },
    { view: "coworking", label: "Coworking", name: "Coworking: your booked and the open sessions" },
    { view: "jobs", label: "Jobs", name: "Jobs: open hiring posts" },
    { view: "lockin", label: "LockIn", name: "LockIn: co-working session and checklist" }
  ]

  Item {
    Plugin.TabRow {
      id: defaultRow
      width: Style.space(check.widths[0])
      tabs: check.sixTabs
      current: "events"
    }

    Plugin.TabRow {
      id: smallestRow
      width: Style.space(check.widths[1])
      tabs: check.sixTabs
      current: "events"
    }
  }

  function report(row, units) {
    var problems = []
    var tabs = []
    var actives = []
    for (var i = 0; i < row.children.length; i++) {
      var c = row.children[i]
      if (c.view === undefined) continue
      tabs.push(c)
      if (c.active) actives.push(c.view)
      if (c.width <= 0 || c.height <= 0) problems.push(c.view + " has no size")
      if (c.x < 0 || c.x + c.width > row.width + 0.5) problems.push(c.view + " is clipped")
      if (c.y < 0 || c.y + c.height > row.height + 0.5) problems.push(c.view + " is outside the row")
      if (String(c.Accessible.name) === "" || String(c.tooltipText) === "") problems.push(c.view + " has no name")
    }
    for (var a = 0; a < tabs.length; a++)
      for (var b = a + 1; b < tabs.length; b++) {
        var p = tabs[a], q = tabs[b]
        if (p.x < q.x + q.width && q.x < p.x + p.width && p.y < q.y + q.height && q.y < p.y + p.height)
          problems.push(p.view + " overlaps " + q.view)
      }
    if (tabs.length !== 6) problems.push("expected 6 tabs, found " + tabs.length)
    if (actives.join(",") !== "events") problems.push("active tab is '" + actives.join(",") + "'")
    console.warn("TABROW width=" + units + " tabs=" + tabs.length
      + " rows=" + Math.round(row.height / tabs[0].height)
      + (problems.length ? " FAIL " + problems.join("; ") : " OK"))
  }

  Timer {
    interval: 300
    running: true
    onTriggered: {
      check.report(defaultRow, check.widths[0])
      check.report(smallestRow, check.widths[1])
      Qt.quit()
    }
  }
}
