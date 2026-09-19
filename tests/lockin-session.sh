#!/usr/bin/env bash
# LockIn start/finish helper and QML contract tests. No network. No live key.
set -euo pipefail

root=$(cd "$(dirname -- "$0")/.." && pwd)
tinkerer="$root/bin/tinkerer"
panel="$root/Panel.qml"
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

BASE_URL="https://lockin-session.test.invalid"

assert_no_key() {
  local label="$1" stdout="$2" stderr="$3"
  case "$stdout$stderr" in
    *"$TEST_KEY"*) bad "$label leaked key" ;;
    *) pass "$label no key leak" ;;
  esac
}

assert_fail_envelope() {
  local label="$1" out="$2"
  if printf '%s' "$out" | jq -e '.ok == false and (.error | type == "string") and has("hint")' >/dev/null 2>&1; then
    pass "$label error+hint keys"
  else
    bad "$label error+hint keys"
    printf '  out=%s\n' "$out"
  fi
}

assert_post_start() {
  local label="$1" want_body="$2"
  local log body
  log=$(cat "$CURL_LOG")
  case "$log" in
    *"-X POST"*) pass "$label POST" ;;
    *) bad "$label missing -X POST"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"/api/v1/lockIn/start"*) pass "$label lockIn/start URL" ;;
    *) bad "$label URL"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"app.tinkerer.club"*) bad "$label hit live origin" ;;
    *) pass "$label no live origin" ;;
  esac
  body=$(printf '%s' "$log" | sed -n 's/.*--data \(.*\) -o .*/\1/p')
  if [ -n "$want_body" ] && [ "$body" = "$want_body" ]; then
    pass "$label POST body $want_body"
  elif [ -z "$want_body" ] && { [ "$body" = "{}" ] || [ -z "$body" ]; }; then
    pass "$label POST body {}"
  else
    bad "$label POST body"
    printf '  body=%s want=%s log=%s\n' "$body" "$want_body" "$log"
  fi
  case "$log" in
    *"/api/v1/lockIn/finish"*|*"/api/v1/lockIn/state"*|*"/api/v1/lockIn/todos"*)
      bad "$label called other lockIn endpoints"
      printf '  log=%s\n' "$log"
      ;;
    *) pass "$label no other lockIn endpoints" ;;
  esac
}

assert_post_finish() {
  local label="$1" want_id="$2"
  local log body
  log=$(cat "$CURL_LOG")
  case "$log" in
    *"-X POST"*) pass "$label POST" ;;
    *) bad "$label missing -X POST"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"/api/v1/lockIn/finish"*) pass "$label lockIn/finish URL" ;;
    *) bad "$label URL"; printf '  log=%s\n' "$log" ;;
  esac
  body=$(printf '%s' "$log" | grep -oE '\{"id":"[^"]*"\}' | head -1 || true)
  if [ -n "$body" ] && printf '%s' "$body" | jq -e --arg id "$want_id" '.id == $id and (keys == ["id"])' >/dev/null 2>&1; then
    pass "$label POST body {id:$want_id}"
  else
    bad "$label POST body"
    printf '  body=%s log=%s\n' "$body" "$log"
  fi
  case "$log" in
    *"/api/v1/lockIn/start"*|*"/api/v1/lockIn/state"*|*"/api/v1/lockIn/todos"*)
      bad "$label called other lockIn endpoints"
      printf '  log=%s\n' "$log"
      ;;
    *) pass "$label no other lockIn endpoints" ;;
  esac
}

# --- lockin start without title ------------------------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/lockin-start-empty.in.json"
export CURL_CODE=200
err_file="$work/err.start-empty"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" lockin start 2>"$err_file") || rc=$?
err=$(cat "$err_file")
want=$(jq -c . "$root/tests/fixtures/lockin-start-empty.out.json")
got=$(printf '%s' "$out" | jq -c .)
if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
  pass "start empty title"
else
  bad "start empty title"
  printf '  rc=%s got=%s want=%s\n' "$rc" "$got" "$want"
fi
assert_post_start "start empty title" ""
assert_no_key "start empty title" "$out" "$err"

# --- lockin start with title ---------------------------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/lockin-start-title.in.json"
export CURL_CODE=200
err_file="$work/err.start-title"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" lockin start Focus time 2>"$err_file") || rc=$?
err=$(cat "$err_file")
want=$(jq -c . "$root/tests/fixtures/lockin-start-title.out.json")
got=$(printf '%s' "$out" | jq -c .)
if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
  pass "start with title"
else
  bad "start with title"
  printf '  rc=%s got=%s want=%s\n' "$rc" "$got" "$want"
fi
assert_post_start "start with title" '{"title":"Focus time"}'
assert_no_key "start with title" "$out" "$err"

# --- lockin start truncates title to 160 ---------------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/lockin-start-empty.in.json"
export CURL_CODE=200
long_title=$(python3 - <<'PY'
print("x" * 200)
PY
)
err_file="$work/err.start-trunc"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" lockin start "$long_title" 2>"$err_file") || rc=$?
log=$(cat "$CURL_LOG")
body=$(printf '%s' "$log" | grep -oE '\{"title":"[^"]*"\}' | head -1 || true)
if [ "$rc" -eq 0 ] && printf '%s' "$body" | jq -e '.title | length == 160' >/dev/null 2>&1; then
  pass "start truncates title"
else
  bad "start truncates title"
  printf '  rc=%s body=%s\n' "$rc" "$body"
fi

# --- lockin finish -------------------------------------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/lockin-finish.in.json"
export CURL_CODE=200
err_file="$work/err.finish"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" lockin finish sess-abc 2>"$err_file") || rc=$?
err=$(cat "$err_file")
want=$(jq -c . "$root/tests/fixtures/lockin-finish.out.json")
got=$(printf '%s' "$out" | jq -c .)
if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
  pass "finish by id"
else
  bad "finish by id"
  printf '  rc=%s got=%s want=%s\n' "$rc" "$got" "$want"
fi
assert_post_finish "finish by id" "sess-abc"
assert_no_key "finish by id" "$out" "$err"

# --- finish missing id: no curl ------------------------------------------------

: > "$CURL_LOG"
err_file="$work/err.finish-missing"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" lockin finish 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1 \
   && printf '%s' "$out" | grep -qi 'id' \
   && [ ! -s "$CURL_LOG" ]; then
  pass "finish missing id no curl"
else
  bad "finish missing id"
  printf '  rc=%s out=%s log=%s\n' "$rc" "$out" "$(cat "$CURL_LOG")"
fi
assert_fail_envelope "finish missing id" "$out"
assert_no_key "finish missing id" "$out" "$err"

# --- start 401 -----------------------------------------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/lockin-start-401.in.json"
export CURL_CODE=401
err_file="$work/err.start401"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" lockin start 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "start 401 ok:false"
else
  bad "start 401 envelope"
  printf '  rc=%s out=%s\n' "$rc" "$out"
fi
assert_fail_envelope "start 401" "$out"
assert_no_key "start 401" "$out" "$err"

# --- usage lists start and finish ----------------------------------------------

if "$tinkerer" -h 2>/dev/null | grep -q 'lockin start'; then
  pass "usage lists lockin start"
else
  bad "usage lists lockin start"
fi
if "$tinkerer" -h 2>/dev/null | grep -q 'lockin finish'; then
  pass "usage lists lockin finish"
else
  bad "usage lists lockin finish"
fi
if "$tinkerer" -h 2>/dev/null | grep -q 'lockin todos'; then
  pass "usage lists lockin todos"
else
  bad "usage lists lockin todos"
fi

# --- helper isolation ----------------------------------------------------------

if python3 - "$tinkerer" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]).read_text()
start = p[p.find("cmd_lockin_start()"):p.find("cmd_lockin_finish()")]
finish = p[p.find("cmd_lockin_finish()"):p.find("unwrap_lockin_todos()")]
ok = "lockIn/start" in start and "lockIn/finish" not in start and "lockIn/todos" not in start
ok = ok and "lockIn/finish" in finish and "lockIn/start" not in finish and "lockIn/todos" not in finish
sys.exit(0 if ok else 1)
PY
then
  pass "helper start/finish isolated"
else
  bad "helper start/finish isolated"
fi

# --- QML start/finish/watchdog contract ----------------------------------------

if grep -q 'text: "Start"' "$panel" && grep -q 'text: "Finish"' "$panel"; then
  pass "QML Start and Finish controls"
else
  bad "QML Start and Finish controls"
fi

if grep -q 'function lockinStart' "$panel" && grep -q 'function lockinFinish' "$panel"; then
  pass "QML lockinStart/lockinFinish functions"
else
  bad "QML lockinStart/lockinFinish functions"
fi

if grep -q 'function checkLockinWatchdog' "$panel" && grep -q 'lockinWatchdogPending' "$panel"; then
  pass "QML watchdog helpers"
else
  bad "QML watchdog helpers"
fi

if grep -q 'id: startProc' "$panel" && grep -q 'id: finishProc' "$panel"; then
  pass "QML startProc/finishProc"
else
  bad "QML startProc/finishProc"
fi

if grep -q 'refreshLockinState()' "$panel" && grep -q 'function applyLockinStart' "$panel" && grep -q 'function applyLockinFinish' "$panel"; then
  pass "QML refetch after mutations"
else
  bad "QML refetch after mutations"
fi

if grep -q 'lockinEarlyFinish' "$panel" && grep -q '30' "$panel"; then
  pass "QML early-finish reward copy"
else
  bad "QML early-finish reward copy"
fi

if grep -q 'maximumLength: 160' "$panel"; then
  pass "QML title max 160"
else
  bad "QML title max 160"
fi

if python3 - "$panel" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]).read_text()
timer = p[p.find("Timer {"):p.find("Timer {", p.find("Timer {") + 1)]
ok = "checkLockinWatchdog()" in timer and "30000" in p
ok = ok and '["lockin", "finish"' in p and '["lockin", "start"' in p
sys.exit(0 if ok else 1)
PY
then
  pass "QML watchdog timer wiring"
else
  bad "QML watchdog timer wiring"
fi

if grep -q 'cmd_lockin_todos' "$tinkerer"; then
  pass "bin/tinkerer has todos commands"
else
  bad "bin/tinkerer has todos commands"
fi

# --- regression: lockin-state.sh still passes ----------------------------------

if "$root/tests/lockin-state.sh" >/dev/null; then
  pass "lockin-state.sh regression"
else
  bad "lockin-state.sh regression"
fi

[ "$fail" -eq 0 ]
