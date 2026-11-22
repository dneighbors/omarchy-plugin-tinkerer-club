#!/usr/bin/env bash
# Upcoming events (event.calendar) helper and QML contract tests. No network. No live key.
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

# shellcheck source=tests/lib/assert-curl-auth.sh
source "$root/tests/lib/assert-curl-auth.sh"
"$root/tests/lib/install-fake-curl.sh" "$work"
export CURL_LOG="$work/curl.log"
export PATH="$work/bin:$PATH"
# Fixed clock: 2026-11-21T19:00:00Z.
export TINKERER_NOW=1795287600

BASE_URL="https://cal.test.invalid"
run_upcoming() {
  "$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" "$@" events upcoming
}

assert_post_calendar() {
  local label="$1" log
  log=$(cat "$CURL_LOG")
  case "$log" in
    *"-X POST"*) pass "$label POST" ;;
    *) bad "$label missing -X POST"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"/api/v1/event/calendar"*) pass "$label calendar URL" ;;
    *) bad "$label URL"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"app.tinkerer.club"*) bad "$label hit live origin" ;;
    *) pass "$label no live origin" ;;
  esac
  assert_api_key_via_header_file "$label" "$log" "$TEST_KEY"
  # 62-day window from the fixed clock (the API rejects anything longer).
  case "$log" in
    *'--data {"from":"2026-11-21T19:00:00Z","to":"2027-01-22T19:00:00Z"}'*) pass "$label 62-day window body" ;;
    *) bad "$label 62-day window body"; printf '  log=%s\n' "$log" ;;
  esac
}

for name in \
  calendar-upcoming \
  calendar-past-and-canceled \
  calendar-empty \
  calendar-recurring-unsafe
do
  : > "$CURL_LOG"
  export CURL_BODY="$root/tests/fixtures/${name}.in.json"
  export CURL_CODE=200
  rc=0
  out=$(run_upcoming 2>"$work/err") || rc=$?
  err=$(cat "$work/err")
  want=$(jq -c . "$root/tests/fixtures/${name}.out.json")
  got=$(printf '%s' "$out" | jq -c .)
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
    pass "success $name"
  else
    bad "success $name"
    printf '  rc=%s\n  got=%s\n  want=%s\n' "$rc" "$got" "$want"
  fi
  assert_post_calendar "success $name"
  case "$out$err" in
    *"$TEST_KEY"*) bad "success $name leaked key" ;;
    *) pass "success $name no key leak" ;;
  esac
done

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/calendar-upcoming.in.json"
export CURL_CODE=200
out=$(run_upcoming --limit 2)
if printf '%s' "$out" | jq -e '.ok == true and (.events | length) == 2 and .events[0].id == "evt-now"' >/dev/null 2>&1; then
  pass "limit caps the list"
else
  bad "limit caps the list"; printf '  out=%s\n' "$out"
fi

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/calendar-401.in.json"
export CURL_CODE=401
out=$(run_upcoming 2>"$work/err") || true
if printf '%s' "$out" | jq -e '.ok == false and .error == "Authentication failed." and has("hint")' >/dev/null 2>&1; then
  pass "401 auth envelope"
else
  bad "401 auth envelope"; printf '  out=%s\n' "$out"
fi
case "$out$(cat "$work/err")" in
  *"$TEST_KEY"*) bad "401 leaked key" ;;
  *) pass "401 no key leak" ;;
esac

# --- QML contracts (no QML runner; source assertions) ------------------------

panel="$root/Panel.qml"

grep -q 'id: eventsProc' "$panel" && pass "Panel eventsProc" || bad "Panel eventsProc"
grep -q '"events", "upcoming"' "$panel" && pass "Panel cmd events upcoming" || bad "Panel cmd events upcoming"
grep -q 'function applyEvents' "$panel" && pass "Panel applyEvents" || bad "Panel applyEvents"
grep -q 'text: "Events"' "$panel" && pass "Panel Events tab" || bad "Panel Events tab"
grep -q 'id: eventsFlick' "$panel" && pass "Panel events list" || bad "Panel events list"
grep -q 'root.eventWhen(modelData.startsAt' "$panel" && pass "Panel event time" || bad "Panel event time"
grep -q 'onClicked: root.openUrl(modelData.url)' "$panel" && pass "Panel event row opens link" || bad "Panel event row opens link"
grep -q 'No upcoming events.' "$panel" && pass "Panel events empty state" || bad "Panel events empty state"

[ "$fail" -eq 0 ]
