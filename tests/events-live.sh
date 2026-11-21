#!/usr/bin/env bash
# Live event banner helper and QML contract tests. No network. No live key.
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

TEST_KEY="test-key-not-real-SECRET99"
key_file="$work/key"
printf '%s\n' "$TEST_KEY" > "$key_file"

# shellcheck source=tests/lib/assert-curl-auth.sh
source "$root/tests/lib/assert-curl-auth.sh"
"$root/tests/lib/install-fake-curl.sh" "$work"
export CURL_LOG="$work/curl.log"
export PATH="$work/bin:$PATH"
# Fixed clock: 2026-11-21T19:00:00Z, one hour after the "live" fixture began.
export TINKERER_NOW=1795287600

BASE_URL="https://live.test.invalid"
run_live() {
  "$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" events live
}

assert_post_live() {
  local label="$1" log
  log=$(cat "$CURL_LOG")
  case "$log" in
    *"-X POST"*) pass "$label POST" ;;
    *) bad "$label missing -X POST"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"/api/v1/event/liveBanner"*) pass "$label liveBanner URL" ;;
    *) bad "$label URL"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"app.tinkerer.club"*) bad "$label hit live origin" ;;
    *) pass "$label no live origin" ;;
  esac
  assert_api_key_via_header_file "$label" "$log" "$TEST_KEY"
  case "$log" in
    *"--data {}"*|*"--data '{}'"*) pass "$label POST body {}" ;;
    *) bad "$label POST body {}"; printf '  log=%s\n' "$log" ;;
  esac
}

for name in \
  live-banner-live \
  live-banner-upcoming \
  live-banner-started-no-status \
  live-banner-none \
  live-banner-ended \
  live-banner-past-window \
  live-banner-unsafe-url
do
  : > "$CURL_LOG"
  export CURL_BODY="$root/tests/fixtures/${name}.in.json"
  export CURL_CODE=200
  rc=0
  out=$(run_live 2>"$work/err") || rc=$?
  err=$(cat "$work/err")
  want=$(jq -c . "$root/tests/fixtures/${name}.out.json")
  got=$(printf '%s' "$out" | jq -c .)
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
    pass "success $name"
  else
    bad "success $name"
    printf '  rc=%s\n  got=%s\n  want=%s\n' "$rc" "$got" "$want"
  fi
  assert_post_live "success $name"
  case "$out$err" in
    *"$TEST_KEY"*) bad "success $name leaked key" ;;
    *) pass "success $name no key leak" ;;
  esac
done

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/live-banner-401.in.json"
export CURL_CODE=401
out=$(run_live 2>"$work/err") || true
if printf '%s' "$out" | jq -e '.ok == false and .error == "Authentication failed." and has("hint")' >/dev/null 2>&1; then
  pass "401 auth envelope"
else
  bad "401 auth envelope"; printf '  out=%s\n' "$out"
fi
case "$out$(cat "$work/err")" in
  *"$TEST_KEY"*) bad "401 leaked key" ;;
  *) pass "401 no key leak" ;;
esac

out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" events nope)
if printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "unknown events subcommand"
else
  bad "unknown events subcommand"
fi

# --- QML contracts (no QML runner; source assertions) ------------------------

panel="$root/Panel.qml"
bar="$root/BarWidget.qml"

grep -q 'id: liveProc' "$panel" && pass "Panel liveProc" || bad "Panel liveProc"
grep -q '"events", "live"' "$panel" && pass "Panel cmd events live" || bad "Panel cmd events live"
grep -q 'function applyLive' "$panel" && pass "Panel applyLive" || bad "Panel applyLive"
grep -q 'id: liveBanner' "$panel" && pass "Panel live banner" || bad "Panel live banner"
grep -q 'root.openUrl(root.liveEvent.url)' "$panel" && pass "Panel banner click opens event" || bad "Panel banner click opens event"
grep -q 'readonly property bool liveNow' "$panel" && pass "Panel liveNow" || bad "Panel liveNow"
grep -q 'panelItem.liveNow === true' "$bar" && pass "BarWidget liveNow" || bad "BarWidget liveNow"
grep -q 'Live now: ' "$bar" && pass "BarWidget live tooltip" || bad "BarWidget live tooltip"

[ "$fail" -eq 0 ]
