#!/usr/bin/env bash
# New-jobs mark: helper (jobs browse --since) and QML contract tests. No network. No live key.
set -euo pipefail

root=$(cd "$(dirname -- "$0")/.." && pwd)
tinkerer="$root/bin/tinkerer"
fail=0

pass() { printf 'ok  %s\n' "$1"; }
bad()  { printf 'not ok  %s\n' "$1"; fail=1; }

[ -x "$tinkerer" ] || { echo "missing $tinkerer"; exit 1; }

unset TINKERER_API_KEY TINKERER_KEY TINKERER_APIKEY 2>/dev/null || true

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
: > "$work/curl.log"

TEST_KEY="test-key-not-real-SECRET77"
key_file="$work/key"
printf '%s\n' "$TEST_KEY" > "$key_file"

"$root/tests/lib/install-fake-curl.sh" "$work"
export CURL_LOG="$work/curl.log"
export PATH="$work/bin:$PATH"

BASE_URL="https://jobs.test.invalid"
run_browse() {
  "$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" jobs browse "$@"
}

check() {
  local label="$1" filter="$2" out
  shift 2
  out=$(run_browse "$@")
  if printf '%s' "$out" | jq -e ".ok == true and ($filter)" >/dev/null 2>&1; then
    pass "$label"
  else
    bad "$label"; printf '  out=%s\n' "$out"
  fi
}

new_ids='[.jobs[] | select(.isNew) | .id]'

# The board: job-new 2026-11-20T12:30, job-mid 2026-11-10, job-old 2026-11-01.
export CURL_BODY="$root/tests/fixtures/jobs-several.in.json"
export CURL_CODE=200

check "first run: nothing is new, and the newest post is the one to remember" \
  ".newCount == 0 and (.jobs | length) == 3 and $new_ids == [] and .seenAt == \"2026-11-20T12:30:00.000Z\""
check "nothing new since the newest post" \
  ".newCount == 0 and $new_ids == [] and .seenAt == \"2026-11-20T12:30:00.000Z\"" \
  --since "2026-11-20T12:30:00.000Z"
check "two new since the oldest post" \
  ".newCount == 2 and $new_ids == [\"job-new\",\"job-mid\"] and .jobs[2].isNew == false and .seenAt == \"2026-11-20T12:30:00.000Z\"" \
  --since "2026-11-01T08:00:00.000Z"
check "one new, with the mark given in another time format" \
  ".newCount == 1 and $new_ids == [\"job-new\"]" \
  --since "2026-11-10T09:15:00Z"
# The newest post I saw has left the board: nothing is new, and the marker
# does not move back to an older post.
check "list got shorter: nothing new, the marker stays" \
  ".newCount == 0 and $new_ids == [] and (.jobs | length) == 3 and .seenAt == \"2026-11-25T00:00:00.000Z\"" \
  --since "2026-11-25T00:00:00.000Z"
check "seen an empty board before: every dated post is new" \
  ".newCount == 3 and .seenAt == \"2026-11-20T12:30:00.000Z\"" \
  --since ""
check "an unreadable mark counts as an empty board, never an error" \
  '.newCount == 3' \
  --since "not a date"

out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" --limit 5 jobs browse --since "2026-11-01T08:00:00.000Z" | jq -c '[.newCount, (.jobs | length)]')
[ "$out" = "[2,3]" ] && pass "the count is the marked rows" || { bad "the count is the marked rows"; printf '  out=%s\n' "$out"; }

# A post with no date is never new.
printf '%s' '{"data":{"items":[{"id":"j-undated","title":"No date"},{"id":"j-dated","title":"Dated","createdAt":"2026-11-21T00:00:00Z"}]}}' > "$work/undated.json"
export CURL_BODY="$work/undated.json"
check "a post with no date is never new" \
  ".newCount == 1 and $new_ids == [\"j-dated\"]" \
  --since "2026-11-20T12:30:00.000Z"

export CURL_BODY="$root/tests/fixtures/jobs-empty.in.json"
check "no jobs: nothing new, the marker stays" \
  '.newCount == 0 and .jobs == [] and .seenAt == "2026-11-20T12:30:00.000Z"' \
  --since "2026-11-20T12:30:00.000Z"

# An API error or a missing key marks nothing.
export CURL_BODY="$root/tests/fixtures/jobs-400.in.json"
export CURL_CODE=400
out=$(run_browse --since "2026-11-01T08:00:00.000Z" 2>/dev/null) || true
if printf '%s' "$out" | jq -e '.ok == false and (has("newCount") | not) and (has("jobs") | not)' >/dev/null 2>&1; then
  pass "API error: nothing marked"
else
  bad "API error: nothing marked"; printf '  out=%s\n' "$out"
fi
: > "$CURL_LOG"
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$work/no-such-key" jobs browse --since "2026-11-01T08:00:00.000Z") || true
if printf '%s' "$out" | jq -e '.ok == false and (has("newCount") | not)' >/dev/null 2>&1 && [ ! -s "$CURL_LOG" ]; then
  pass "no key: nothing marked, no request"
else
  bad "no key: nothing marked, no request"; printf '  out=%s\n' "$out"
fi
out=$(run_browse --bogus) || true
if printf '%s' "$out" | jq -e '.ok == false and .error == "Unknown option: --bogus"' >/dev/null 2>&1; then
  pass "unknown option is refused"
else
  bad "unknown option is refused"; printf '  out=%s\n' "$out"
fi

# --- QML contracts (no QML runner; source assertions) ------------------------

panel="$root/Panel.qml"
bar="$root/BarWidget.qml"

grep -q 'property bool jobsSeenKnown: false' "$panel" && pass "Panel marks nothing before the first open" || bad "Panel marks nothing before the first open"
grep -q 'property string jobsSeenAt: ""' "$panel" && pass "Panel remembers the newest job in memory, like seenId" || bad "Panel remembers the newest job in memory, like seenId"
grep -q '\["jobs", "browse"\].concat(root.jobsSeenKnown ? \["--since", root.jobsSeenAt\] : \[\])' "$panel" && pass "Panel passes the mark to the helper" || bad "Panel passes the mark to the helper"
grep -q 'label: root.jobsNewCount > 0 ? "Jobs \\u00b7 " + root.jobsNewCount : "Jobs"' "$panel" && pass "Panel Jobs tab label carries the count" || bad "Panel Jobs tab label carries the count"
grep -q 'readonly property bool isNew: modelData.isNew === true' "$panel" && pass "Panel rows read isNew" || bad "Panel rows read isNew"
grep -q 'root.plain(\[jobItem.isNew ? "New" : "", jobItem.age\]' "$panel" && pass "Panel row mark through plain()" || bad "Panel row mark through plain()"
# Seen in the tab: the marker moves and the tab mark clears, after the load.
if awk '/^  function applyJobs/ {t=1} t && /root.opened && root.panelView === "jobs"/ {v=1} v && /root.jobsSeenAt = String\(data.seenAt/ {a=1} v && /root.jobsNewCount = 0/ {c=1} t && /^  }/ {t=0} END {exit !(a && c)}' "$panel"; then
  pass "Panel clears the mark once the Jobs tab has loaded"
else
  bad "Panel clears the mark once the Jobs tab has loaded"
fi
# Opened, then left (or closed) before the first load finished: that load
# still sets the marker, and the quiet refresh retries until one does.
grep -q 'if (root.opened && root.panelView === "jobs") root.jobsOpened = true' "$panel" && pass "Panel remembers the Jobs tab was opened" || bad "Panel remembers the Jobs tab was opened"
grep -q '(root.opened && root.panelView === "jobs") || (root.jobsOpened && !root.jobsSeenKnown)' "$panel" && pass "Panel sets the marker on a first load that finishes off the tab" || bad "Panel sets the marker on a first load that finishes off the tab"
[ "$(grep -c 'jobsNewCount = 0' "$panel")" -ge 3 ] && pass "Panel clears the mark on error and without a key" || bad "Panel clears the mark on error and without a key"
# The quiet refresh timer (the one keyed on refreshMinutes) reads the jobs.
if awk '/interval: Math.max\(1, root.refreshMinutes\)/ {t=1} t && /root.jobsSeenKnown \|\| root.jobsOpened\)/ {k=1} t && k && /root.refreshJobs\(\)/ {found=1} t && /^  }/ {t=0} END {exit !found}' "$panel"; then
  pass "Panel quiet refresh reads jobs"
else
  bad "Panel quiet refresh reads jobs"
fi
[ "$(grep -c '^  Timer {' "$panel")" -eq 2 ] && pass "Panel adds no timer" || bad "Panel adds no timer"
grep -qi 'job' "$bar" && bad "BarWidget gains no jobs cue" || pass "BarWidget gains no jobs cue"
grep -q 'jobs' "$root/manifest.json" && bad "no new setting" || pass "no new setting"

[ "$fail" -eq 0 ]
