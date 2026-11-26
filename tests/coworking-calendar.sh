#!/usr/bin/env bash
# Coworking sessions (coworking.calendar) helper and QML contract tests. No network. No live key.
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

TEST_KEY="test-key-not-real-SECRET88"
key_file="$work/key"
printf '%s\n' "$TEST_KEY" > "$key_file"

# shellcheck source=tests/lib/assert-curl-auth.sh
source "$root/tests/lib/assert-curl-auth.sh"
"$root/tests/lib/install-fake-curl.sh" "$work"
export CURL_LOG="$work/curl.log"
export PATH="$work/bin:$PATH"
# Local clock: 2026-11-23T19:00:00Z, two days ahead of the serverNow in the
# fixtures (2026-11-21T19:00:00Z). Sessions on the 22nd must still be listed.
export TINKERER_NOW=1795460400

BASE_URL="https://cw.test.invalid"
run_calendar() {
  "$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" "$@" coworking calendar
}

assert_post_coworking() {
  local label="$1" log
  log=$(cat "$CURL_LOG")
  case "$log" in
    *"-X POST"*) pass "$label POST" ;;
    *) bad "$label missing -X POST"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"/api/v1/coworking/calendar"*) pass "$label coworking URL" ;;
    *) bad "$label URL"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"app.tinkerer.club"*) bad "$label hit live origin" ;;
    *) pass "$label no live origin" ;;
  esac
  assert_api_key_via_header_file "$label" "$log" "$TEST_KEY"
  # 15-day window from the local clock, as the site asks.
  case "$log" in
    *'--data {"from":"2026-11-23T19:00:00Z","to":"2026-12-08T19:00:00Z"}'*) pass "$label 15-day window body" ;;
    *) bad "$label 15-day window body"; printf '  log=%s\n' "$log" ;;
  esac
}

for name in \
  coworking-empty \
  coworking-mine-only \
  coworking-open-only \
  coworking-ended-dropped \
  coworking-unsafe-url
do
  : > "$CURL_LOG"
  export CURL_BODY="$root/tests/fixtures/${name}.in.json"
  export CURL_CODE=200
  rc=0
  out=$(run_calendar 2>"$work/err") || rc=$?
  err=$(cat "$work/err")
  want=$(jq -c . "$root/tests/fixtures/${name}.out.json")
  got=$(printf '%s' "$out" | jq -c .)
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
    pass "success $name"
  else
    bad "success $name"
    printf '  rc=%s\n  got=%s\n  want=%s\n' "$rc" "$got" "$want"
  fi
  assert_post_coworking "success $name"
  case "$out$err" in
    *"$TEST_KEY"*) bad "success $name leaked key" ;;
    *) pass "success $name no key leak" ;;
  esac
done

# Every url the helper prints is http(s) on the configured origin.
: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/coworking-unsafe-url.in.json"
export CURL_CODE=200
out=$(run_calendar)
if printf '%s' "$out" | jq -e --arg o "$BASE_URL/" '(.open | length) == 5 and ([.mine[], .open[]] | all(.url | startswith($o)))' >/dev/null 2>&1; then
  pass "unsafe urls stay on the configured origin"
else
  bad "unsafe urls stay on the configured origin"; printf '  out=%s\n' "$out"
fi

# Without serverNow the helper falls back to its own clock.
: > "$CURL_LOG"
jq -c 'del(.data.serverNow)' "$root/tests/fixtures/coworking-ended-dropped.in.json" > "$work/no-server-now.json"
export CURL_BODY="$work/no-server-now.json"
out=$(run_calendar)
if printf '%s' "$out" | jq -e '.ok == true and .mine == [] and .open == []' >/dev/null 2>&1; then
  pass "local clock used when serverNow is missing"
else
  bad "local clock used when serverNow is missing"; printf '  out=%s\n' "$out"
fi

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/coworking-open-only.in.json"
export CURL_CODE=200
out=$(run_calendar --limit 2)
if printf '%s' "$out" | jq -e '.ok == true and (.open | length) == 2 and .open[0].id == "cw-a" and .open[1].id == "cw-b"' >/dev/null 2>&1; then
  pass "limit caps the list, soonest first"
else
  bad "limit caps the list, soonest first"; printf '  out=%s\n' "$out"
fi

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/coworking-401.in.json"
export CURL_CODE=401
out=$(run_calendar 2>"$work/err") || true
if printf '%s' "$out" | jq -e '.ok == false and .error == "Authentication failed." and has("hint")' >/dev/null 2>&1; then
  pass "401 auth envelope"
else
  bad "401 auth envelope"; printf '  out=%s\n' "$out"
fi
case "$out$(cat "$work/err")" in
  *"$TEST_KEY"*) bad "401 leaked key" ;;
  *) pass "401 no key leak" ;;
esac

: > "$CURL_LOG"
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$work/no-such-key" coworking calendar) || true
if printf '%s' "$out" | jq -e '.ok == false and .error == "Add your Tinkerer Club API key." and (.hint | length) > 0' >/dev/null 2>&1 && [ ! -s "$CURL_LOG" ]; then
  pass "no key gives the setup hint without a request"
else
  bad "no key gives the setup hint without a request"; printf '  out=%s\n' "$out"
fi

# --- QML contracts (no QML runner; source assertions) ------------------------

panel="$root/Panel.qml"

grep -q 'id: coworkingProc' "$panel" && pass "Panel coworkingProc" || bad "Panel coworkingProc"
grep -q '"coworking", "calendar"' "$panel" && pass "Panel cmd coworking calendar" || bad "Panel cmd coworking calendar"
grep -q 'function applyCoworking' "$panel" && pass "Panel applyCoworking" || bad "Panel applyCoworking"
grep -q 'label: "Coworking"' "$panel" && pass "Panel Coworking tab" || bad "Panel Coworking tab"
grep -q 'id: coworkingFlick' "$panel" && pass "Panel coworking list" || bad "Panel coworking list"
grep -q '"Your sessions"' "$panel" && pass "Panel your sessions heading" || bad "Panel your sessions heading"
grep -q '"Open sessions"' "$panel" && pass "Panel open sessions heading" || bad "Panel open sessions heading"
grep -q 'root.eventWhen(modelData.startsAt' "$panel" && pass "Panel session time uses the Events format" || bad "Panel session time uses the Events format"
grep -q 'root.plain(root.coworkingWho(modelData))' "$panel" && pass "Panel session people" || bad "Panel session people"
grep -q 'onClicked: root.openCoworking(modelData.url)' "$panel" && pass "Panel session row opens link" || bad "Panel session row opens link"
grep -q 'function coworkingSafeUrl' "$panel" && pass "Panel checks the link origin" || bad "Panel checks the link origin"
grep -q 'No coworking sessions scheduled.' "$panel" && pass "Panel coworking empty state" || bad "Panel coworking empty state"
grep -q 'root.openUrl(root.coworkingPageUrl())' "$panel" && pass "Panel coworking page link" || bad "Panel coworking page link"
grep -q 'root.panelView === "coworking"' "$panel" && pass "Panel refresh covers coworking" || bad "Panel refresh covers coworking"

[ "$fail" -eq 0 ]
