#!/usr/bin/env bash
# Coworking bar cue: helper and QML contract tests. No network. No live key.
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

BASE_URL="https://cw.test.invalid"
run_calendar() {
  "$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" coworking calendar
}

# The fixture has no serverNow, so TINKERER_NOW is the clock. My one session
# runs 2026-11-23T19:10:00Z to 20:10:00Z; an open session I did not book is in
# progress all along and must never cue.
start=1795461000
export CURL_BODY="$root/tests/fixtures/coworking-cue.in.json"
export CURL_CODE=200

check_cue() {
  local label="$1" now="$2" filter="$3" out
  out=$(TINKERER_NOW="$now" run_calendar)
  if printf '%s' "$out" | jq -e ".ok == true and ($filter)" >/dev/null 2>&1; then
    pass "$label"
  else
    bad "$label"; printf '  out=%s\n' "$out"
  fi
}

check_cue "starts in 10 minutes: cue" $((start - 600)) \
  '.cue.id == "cw-mine" and .cue.isLive == false and .cue.startsAt == "2026-11-23T19:10:00.000Z" and .cue.title == "Deep <b>work</b>" and .cue.url == "https://cw.test.invalid/coworking/cw-mine"'
check_cue "starts in exactly 15 minutes: cue" $((start - 900)) '.cue.id == "cw-mine"'
check_cue "starts in 16 minutes: no cue" $((start - 960)) '.cue == null and (.mine | length) == 1'
check_cue "starts in 2 hours: no cue" $((start - 7200)) '.cue == null and (.mine | length) == 1'
check_cue "in progress: cue" $((start + 1200)) '.cue.id == "cw-mine" and .cue.isLive == true'
check_cue "ended: no cue" $((start + 4800)) '.cue == null and .mine == []'
check_cue "an open session I did not book never cues" $((start - 7200)) '.cue == null and (.open | length) == 1 and .open[0].isLive == true'

# No sessions at all.
export CURL_BODY="$root/tests/fixtures/coworking-empty.in.json"
check_cue "no sessions: no cue" $((start - 600)) '.cue == null'

# A booked session with no end time stops cueing an hour after it started.
printf '%s' '{"data":{"mySessions":[{"id":"cw-open-ended","startsAt":"2026-11-23T19:10:00Z"}]}}' > "$work/no-end.json"
export CURL_BODY="$work/no-end.json"
check_cue "no end time, started 30 minutes ago: cue" $((start + 1800)) '.cue.id == "cw-open-ended"'
check_cue "no end time, started 2 hours ago: no cue" $((start + 7200)) '.cue == null and (.mine | length) == 1'

# An API error or a missing key gives no cue.
export CURL_BODY="$root/tests/fixtures/coworking-401.in.json"
export CURL_CODE=401
out=$(TINKERER_NOW=$((start - 600)) run_calendar 2>/dev/null) || true
if printf '%s' "$out" | jq -e '.ok == false and (has("cue") | not)' >/dev/null 2>&1; then
  pass "API error: no cue"
else
  bad "API error: no cue"; printf '  out=%s\n' "$out"
fi
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$work/no-such-key" coworking calendar) || true
if printf '%s' "$out" | jq -e '.ok == false and (has("cue") | not)' >/dev/null 2>&1; then
  pass "no key: no cue"
else
  bad "no key: no cue"; printf '  out=%s\n' "$out"
fi

# --- QML contracts (no QML runner; source assertions) ------------------------

panel="$root/Panel.qml"
bar="$root/BarWidget.qml"

grep -q 'property var coworkingCue: null' "$panel" && pass "Panel coworkingCue" || bad "Panel coworkingCue"
grep -q 'root.coworkingCue = data.cue && data.cue.id ? data.cue : null' "$panel" && pass "Panel takes the cue from the helper" || bad "Panel takes the cue from the helper"
[ "$(grep -c 'coworkingCue = null' "$panel")" -ge 2 ] && pass "Panel clears the cue on error and without a key" || bad "Panel clears the cue on error and without a key"
grep -q 'return root.plain(root.snippet(coworkingCue.title' "$panel" && pass "Panel cue text through plain()" || bad "Panel cue text through plain()"
grep -q 'function openCoworkingTab' "$panel" && pass "Panel openCoworkingTab" || bad "Panel openCoworkingTab"
# The quiet refresh timer (the one keyed on refreshMinutes) reads the sessions.
if awk '/interval: Math.max\(1, root.refreshMinutes\)/ {t=1} t && /root.refreshCoworking\(\)/ {found=1} t && /^  }/ {t=0} END {exit !found}' "$panel"; then
  pass "Panel quiet refresh reads coworking"
else
  bad "Panel quiet refresh reads coworking"
fi
[ "$(grep -c '^  Timer {' "$panel")" -eq 2 ] && pass "Panel adds no timer" || bad "Panel adds no timer"

grep -q 'panelItem.coworkingSoon === true' "$bar" && pass "BarWidget coworkingSoon" || bad "BarWidget coworkingSoon"
grep -q 'showCoworkingCue: coworkingSoon && !opened && !liveNow && unreadCount <= 0 && !lockinLive' "$bar" && pass "BarWidget cue sits below live, unread and LockIn" || bad "BarWidget cue sits below live, unread and LockIn"
grep -q 'root.hasNew && !root.opened && root.unreadCount <= 0 && !root.lockinLive && !root.showCoworkingCue' "$bar" && pass "BarWidget cue sits above the new-activity dot" || bad "BarWidget cue sits above the new-activity dot"
grep -q '"Tinkerer Club · Coworking: " + root.coworkingCueText' "$bar" && pass "BarWidget cue tooltip" || bad "BarWidget cue tooltip"
grep -q 'visible: root.showCoworkingCue' "$bar" && pass "BarWidget cue mark" || bad "BarWidget cue mark"
grep -q 'panelItem.openCoworkingTab()' "$bar" && pass "BarWidget click opens the Coworking tab" || bad "BarWidget click opens the Coworking tab"

[ "$fail" -eq 0 ]
