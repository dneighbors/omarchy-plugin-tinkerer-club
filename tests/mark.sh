#!/usr/bin/env bash
# Mark-read / mark-all-read helper and fixture tests. No network. No live key.
set -euo pipefail

root=$(cd "$(dirname -- "$0")/.." && pwd)
tinkerer="$root/bin/tinkerer"
fail=0

pass() { printf 'ok  %s\n' "$1"; }
bad()  { printf 'not ok  %s\n' "$1"; fail=1; }

[ -x "$tinkerer" ] || { echo "missing $tinkerer"; exit 1; }

# Task 2.8: never use a live TINKERER key even if the environment has one.
unset TINKERER_API_KEY TINKERER_KEY TINKERER_APIKEY 2>/dev/null || true

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
: > "$work/curl.log"

# Distinctive dummy — must never appear in helper stdout/stderr.
TEST_KEY="test-key-not-real-SECRET99"
key_file="$work/key"
printf '%s\n' "$TEST_KEY" > "$key_file"

# shellcheck source=tests/lib/assert-curl-auth.sh
source "$root/tests/lib/assert-curl-auth.sh"
"$root/tests/lib/install-fake-curl.sh" "$work"
export CURL_LOG="$work/curl.log"
export PATH="$work/bin:$PATH"

BASE_URL="https://mark.test.invalid"
run_mark_read() {
  "$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" "$@" notifications mark-read n1
}
run_mark_all() {
  "$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" "$@" notifications mark-all-read
}

assert_no_key() {
  local label="$1" stdout="$2" stderr="$3"
  case "$stdout$stderr" in
    *"$TEST_KEY"*) bad "$label leaked key" ;;
    *) pass "$label no key leak" ;;
  esac
}

assert_post_mark_read() {
  local label="$1" log body
  log=$(cat "$CURL_LOG")
  case "$log" in
    *"-X POST"*) pass "$label POST" ;;
    *) bad "$label missing -X POST"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"/api/v1/notification/markRead"*) pass "$label markRead URL" ;;
    *) bad "$label URL"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"app.tinkerer.club"*) bad "$label hit live origin" ;;
    *) pass "$label no live origin" ;;
  esac
  case "$log" in
    *"Content-Type: application/json"*) pass "$label Content-Type" ;;
    *) bad "$label Content-Type"; printf '  log=%s\n' "$log" ;;
  esac
  assert_api_key_via_header_file "$label" "$log" "$TEST_KEY"
  body=$(printf '%s' "$log" | grep -oE '\{"id":"[^"]*"\}' | head -1 || true)
  if [ -n "$body" ] && printf '%s' "$body" | jq -e '.id == "n1" and (keys == ["id"])' >/dev/null 2>&1; then
    pass "$label POST body {id:n1} only"
  else
    bad "$label POST body"
    printf '  body=%s log=%s\n' "$body" "$log"
  fi
  case "$log" in
    *"/api/v1/notification/list"*|*"notification/unreadCount"*|*"notification/markAllRead"*)
      bad "$label called list/unread/markAll"
      printf '  log=%s\n' "$log"
      ;;
    *) pass "$label no other notification endpoints" ;;
  esac
}

assert_post_mark_all() {
  local label="$1" log
  log=$(cat "$CURL_LOG")
  case "$log" in
    *"-X POST"*) pass "$label POST" ;;
    *) bad "$label missing -X POST"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"/api/v1/notification/markAllRead"*) pass "$label markAllRead URL" ;;
    *) bad "$label URL"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"app.tinkerer.club"*) bad "$label hit live origin" ;;
    *) pass "$label no live origin" ;;
  esac
  case "$log" in
    *"Content-Type: application/json"*) pass "$label Content-Type" ;;
    *) bad "$label Content-Type"; printf '  log=%s\n' "$log" ;;
  esac
  assert_api_key_via_header_file "$label" "$log" "$TEST_KEY"
  case "$log" in
    *"--data {}"*|*"--data '{}'"*) pass "$label POST body {}" ;;
    *) bad "$label POST body {}"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"/api/v1/notification/list"*|*"notification/unreadCount"*|*"notification/markRead"*)
      bad "$label called list/unread/markRead"
      printf '  log=%s\n' "$log"
      ;;
    *) pass "$label no other notification endpoints" ;;
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

# --- successful unwrap fixtures (mark-read) ----------------------------------

for name in \
  mark-read-empty \
  mark-read-data-wrapped \
  mark-read-result-data
do
  : > "$CURL_LOG"
  export CURL_BODY="$root/tests/fixtures/${name}.in.json"
  export CURL_CODE=200
  err_file="$work/err.$name"
  rc=0
  out=$(run_mark_read 2>"$err_file") || rc=$?
  err=$(cat "$err_file")
  want=$(jq -c . "$root/tests/fixtures/${name}.out.json")
  got=$(printf '%s' "$out" | jq -c .)
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
    pass "success $name"
  else
    bad "success $name"
    printf '  rc=%s\n  got=%s\n  want=%s\n' "$rc" "$got" "$want"
  fi
  lines=$(printf '%s\n' "$out" | wc -l)
  [ "$lines" -eq 1 ] || bad "success $name not one line ($lines)"
  if printf '%s' "$got" | jq -e '.ok == true and .id == "n1"' >/dev/null 2>&1; then
    pass "success $name ok+id"
  else
    bad "success $name ok+id"
  fi
  assert_post_mark_read "success $name"
  assert_no_key "success $name" "$out" "$err"
done

# --- successful unwrap fixtures (mark-all-read) ------------------------------

for name in \
  mark-all-empty \
  mark-all-data-wrapped \
  mark-all-result-data
do
  : > "$CURL_LOG"
  export CURL_BODY="$root/tests/fixtures/${name}.in.json"
  export CURL_CODE=200
  err_file="$work/err.$name"
  rc=0
  out=$(run_mark_all 2>"$err_file") || rc=$?
  err=$(cat "$err_file")
  want=$(jq -c . "$root/tests/fixtures/${name}.out.json")
  got=$(printf '%s' "$out" | jq -c .)
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
    pass "success $name"
  else
    bad "success $name"
    printf '  rc=%s\n  got=%s\n  want=%s\n' "$rc" "$got" "$want"
  fi
  lines=$(printf '%s\n' "$out" | wc -l)
  [ "$lines" -eq 1 ] || bad "success $name not one line ($lines)"
  if printf '%s' "$got" | jq -e '.ok == true and (has("id") | not)' >/dev/null 2>&1; then
    pass "success $name ok no id"
  else
    bad "success $name ok no id"
  fi
  assert_post_mark_all "success $name"
  assert_no_key "success $name" "$out" "$err"
done

# --- extra unwrap: pass-through {ok:false}; any other JSON is success --------

run_read_payload() {
  printf '%s' "$1" > "$work/extra.in.json"
  : > "$CURL_LOG"
  export CURL_BODY="$work/extra.in.json"
  export CURL_CODE=200
  run_mark_read
}

got=$(run_read_payload '{"ok":false,"error":"upstream","hint":""}' | jq -c .)
[ "$got" = '{"ok":false,"error":"upstream","hint":""}' ] \
  && pass "pass-through ok:false" || bad "pass-through ok:false ($got)"

got=$(run_read_payload '{"json":{}}' | jq -c .)
[ "$got" = '{"ok":true,"id":"n1"}' ] \
  && pass "unwrap json wrapper" || bad "unwrap json wrapper ($got)"

# --- 401 auth, mention key file, never the key (both commands) ---------------

for cmd in mark-read mark-all-read; do
  : > "$CURL_LOG"
  export CURL_BODY="$root/tests/fixtures/mark-401.in.json"
  export CURL_CODE=401
  err_file="$work/err.401.$cmd"
  rc=0
  if [ "$cmd" = "mark-read" ]; then
    out=$(run_mark_read 2>"$err_file") || rc=$?
  else
    out=$(run_mark_all 2>"$err_file") || rc=$?
  fi
  err=$(cat "$err_file")
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1; then
    pass "401 $cmd ok:false"
  else
    bad "401 $cmd envelope"
    printf '  rc=%s out=%s\n' "$rc" "$out"
  fi
  if printf '%s' "$out" | grep -qi 'key file'; then
    pass "401 $cmd mentions key file"
  else
    bad "401 $cmd mentions key file"
    printf '  out=%s\n' "$out"
  fi
  if [ "$cmd" = "mark-read" ]; then
    assert_post_mark_read "401 $cmd"
  else
    assert_post_mark_all "401 $cmd"
  fi
  assert_fail_envelope "401 $cmd" "$out"
  assert_no_key "401 $cmd" "$out" "$err"
done

# --- 403 same auth envelope as 401 -------------------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/mark-401.in.json"
export CURL_CODE=403
err_file="$work/err.403"
rc=0
out=$(run_mark_read 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1 \
   && printf '%s' "$out" | grep -qi 'key file'; then
  pass "403 auth envelope"
else
  bad "403 auth envelope"
  printf '  rc=%s out=%s\n' "$rc" "$out"
fi
assert_post_mark_read "403"
assert_fail_envelope "403" "$out"
assert_no_key "403" "$out" "$err"

# --- empty key file: no curl, empty-file error -------------------------------

: > "$CURL_LOG"
unset CURL_BODY
export CURL_CODE=200
empty_key="$work/empty-key"
: > "$empty_key"
err_file="$work/err.emptykey"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$empty_key" notifications mark-read n1 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1 \
   && printf '%s' "$out" | grep -qi 'empty' \
   && [ ! -s "$CURL_LOG" ]; then
  pass "empty key file no curl"
else
  bad "empty key file"
  printf '  rc=%s out=%s log=%s\n' "$rc" "$out" "$(cat "$CURL_LOG")"
fi
assert_fail_envelope "empty key file" "$out"
assert_no_key "empty key file" "$out" "$err"

# --- non-JSON payload --------------------------------------------------------

printf 'not-json\n' > "$work/nonjson.in"
for cmd in read all; do
  : > "$CURL_LOG"
  export CURL_BODY="$work/nonjson.in"
  export CURL_CODE=200
  err_file="$work/err.nonjson.$cmd"
  rc=0
  if [ "$cmd" = read ]; then
    out=$(run_mark_read 2>"$err_file") || rc=$?
  else
    out=$(run_mark_all 2>"$err_file") || rc=$?
  fi
  err=$(cat "$err_file")
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1 \
     && printf '%s' "$out" | grep -qi 'json'; then
    pass "non-JSON $cmd ok:false"
  else
    bad "non-JSON $cmd"
    printf '  rc=%s out=%s\n' "$rc" "$out"
  fi
  assert_fail_envelope "non-JSON $cmd" "$out"
  assert_no_key "non-JSON $cmd" "$out" "$err"
done

# --- curl network failure ----------------------------------------------------

: > "$CURL_LOG"
unset CURL_BODY
export CURL_CODE=200
err_file="$work/err.net"
rc=0
out=$(run_mark_read 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1 \
   && printf '%s' "$out" | grep -qi 'network'; then
  pass "network failure ok:false"
else
  bad "network failure"
  printf '  rc=%s out=%s\n' "$rc" "$out"
fi
assert_fail_envelope "network failure" "$out"
assert_no_key "network failure" "$out" "$err"

# --- missing key file: configured-style error, no curl -----------------------

: > "$CURL_LOG"
unset CURL_BODY
export CURL_CODE=200
missing="$work/missing-key"
err_file="$work/err.missing"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$missing" notifications mark-read n1 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1 \
   && printf '%s' "$out" | grep -q 'Add your Tinkerer Club API key.' \
   && [ ! -s "$CURL_LOG" ]; then
  pass "missing key file no curl"
else
  bad "missing key file"
  printf '  rc=%s out=%s log=%s\n' "$rc" "$out" "$(cat "$CURL_LOG")"
fi
assert_fail_envelope "missing key file" "$out"
assert_no_key "missing key file" "$out" "$err"

# --- mark-read missing / empty id: {ok:false}, no curl -----------------------

: > "$CURL_LOG"
unset CURL_BODY
err_file="$work/err.noid"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" notifications mark-read 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1 \
   && printf '%s' "$out" | grep -qi 'id' \
   && [ ! -s "$CURL_LOG" ]; then
  pass "mark-read missing id no curl"
else
  bad "mark-read missing id"
  printf '  rc=%s out=%s log=%s\n' "$rc" "$out" "$(cat "$CURL_LOG")"
fi
assert_fail_envelope "mark-read missing id" "$out"
assert_no_key "mark-read missing id" "$out" "$err"

: > "$CURL_LOG"
err_file="$work/err.emptyid"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" notifications mark-read "" 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1 \
   && printf '%s' "$out" | grep -qi 'id' \
   && [ ! -s "$CURL_LOG" ]; then
  pass "mark-read empty id no curl"
else
  bad "mark-read empty id"
  printf '  rc=%s out=%s log=%s\n' "$rc" "$out" "$(cat "$CURL_LOG")"
fi
assert_fail_envelope "mark-read empty id" "$out"
assert_no_key "mark-read empty id" "$out" "$err"

# --- unknown notifications subcommands: frob, mark, markRead -----------------

for sub in frob mark markRead; do
  : > "$CURL_LOG"
  err_file="$work/err.$sub"
  rc=0
  out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" notifications "$sub" 2>"$err_file") || rc=$?
  err=$(cat "$err_file")
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1 \
     && printf '%s' "$out" | grep -q "$sub" \
     && [ ! -s "$CURL_LOG" ]; then
    pass "unknown notifications $sub"
  else
    bad "unknown notifications $sub"
    printf '  rc=%s out=%s log=%s\n' "$rc" "$out" "$(cat "$CURL_LOG")"
  fi
  assert_no_key "unknown $sub" "$out" "$err"
done

# --- notifications unread still hits unreadCount only ------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/unread-bare-number.in.json"
export CURL_CODE=200
err_file="$work/err.unread"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" notifications unread 2>"$err_file") || rc=$?
err=$(cat "$err_file")
log=$(cat "$CURL_LOG")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == true and (.count | type == "number")' >/dev/null 2>&1; then
  pass "unread still dispatches"
else
  bad "unread still dispatches"
  printf '  rc=%s out=%s\n' "$rc" "$out"
fi
case "$log" in
  *"/api/v1/notification/list"*|*"notification/markRead"*|*"notification/markAllRead"*)
    bad "unread called list/mark"
    printf '  log=%s\n' "$log"
    ;;
  *"/api/v1/notification/unreadCount"*) pass "unread still hits unreadCount" ;;
  *) bad "unread URL"; printf '  log=%s\n' "$log" ;;
esac
assert_no_key "unread" "$out" "$err"

# --- notifications list still hits list only ---------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/list-empty.in.json"
export CURL_CODE=200
err_file="$work/err.list"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" notifications list 2>"$err_file") || rc=$?
err=$(cat "$err_file")
log=$(cat "$CURL_LOG")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == true and (.notifications | type == "array")' >/dev/null 2>&1; then
  pass "list still dispatches"
else
  bad "list still dispatches"
  printf '  rc=%s out=%s\n' "$rc" "$out"
fi
case "$log" in
  *"notification/unreadCount"*|*"notification/markRead"*|*"notification/markAllRead"*)
    bad "list called unread/mark"
    printf '  log=%s\n' "$log"
    ;;
  *"/api/v1/notification/list"*) pass "list still hits list" ;;
  *) bad "list URL"; printf '  log=%s\n' "$log" ;;
esac
assert_no_key "list" "$out" "$err"

# --- status still configured, never calls curl -------------------------------

: > "$CURL_LOG"
err_file="$work/err.status"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" status 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == true and .configured == true' >/dev/null 2>&1 \
   && [ ! -s "$CURL_LOG" ]; then
  pass "status configured without curl"
else
  bad "status configured without curl"
  printf '  rc=%s out=%s log=%s\n' "$rc" "$out" "$(cat "$CURL_LOG")"
fi
assert_no_key "status" "$out" "$err"

# --- feed dispatch still present; hits post/timeline only --------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/list-empty.in.json"
export CURL_CODE=200
err_file="$work/err.feed"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" feed 2>"$err_file") || rc=$?
err=$(cat "$err_file")
log=$(cat "$CURL_LOG")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == true and (.posts | type == "array")' >/dev/null 2>&1; then
  pass "feed still dispatches"
else
  bad "feed still dispatches"
  printf '  rc=%s out=%s\n' "$rc" "$out"
fi
case "$log" in
  *"/api/v1/notification/list"*|*"notification/unreadCount"*|*"notification/markRead"*|*"notification/markAllRead"*)
    bad "feed called notification endpoints"
    printf '  log=%s\n' "$log"
    ;;
  *"/api/v1/post/timeline"*) pass "feed still hits timeline" ;;
  *) bad "feed URL"; printf '  log=%s\n' "$log" ;;
esac
assert_no_key "feed" "$out" "$err"

# --- usage names kebab-case mark commands; no camelCase ----------------------

if "$tinkerer" -h 2>/dev/null | grep -q 'notifications mark-read'; then
  pass "usage lists notifications mark-read"
else
  bad "usage lists notifications mark-read"
fi
if "$tinkerer" -h 2>/dev/null | grep -q 'notifications mark-all-read'; then
  pass "usage lists notifications mark-all-read"
else
  bad "usage lists notifications mark-all-read"
fi
if "$tinkerer" -h 2>/dev/null | grep -q 'notifications unread'; then
  pass "usage lists notifications unread"
else
  bad "usage lists notifications unread"
fi
if "$tinkerer" -h 2>/dev/null | grep -q 'notifications list'; then
  pass "usage lists notifications list"
else
  bad "usage lists notifications list"
fi
if "$tinkerer" -h 2>/dev/null | grep -Eq 'notifications markRead|notifications markAllRead'; then
  bad "usage lists camelCase mark commands"
else
  pass "usage has no camelCase mark commands"
fi

if grep -q 'status)' "$tinkerer" && grep -q 'feed)' "$tinkerer"; then
  pass "status and feed dispatch remain"
else
  bad "status and feed dispatch remain"
fi

# Task 1.8: mark commands must not call list or unreadCount.
if python3 - "$tinkerer" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]).read_text()
def fn(name, nxt):
    a = p.find(name)
    b = p.find(nxt, a + 1) if a != -1 else -1
    return p[a:b] if a != -1 and b != -1 else ""
read = fn("cmd_notifications_mark_read()", "cmd_notifications_mark_all_read()")
allr = fn("cmd_notifications_mark_all_read()", "while [[ $# -gt 0 ]]")
ok = "notification/markRead" in read and "notification/list" not in read and "unreadCount" not in read
ok = ok and "notification/markAllRead" in allr and "notification/list" not in allr and "unreadCount" not in allr
ok = ok and "xdg-open" not in read and "xdg-open" not in allr
sys.exit(0 if ok else 1)
PY
then
  pass "helper mark cmds isolated"
else
  bad "helper mark cmds isolated"
fi

panel="$root/Panel.qml"
bar="$root/BarWidget.qml"

# Task 4.3 helper asserts: row openUrl line still exists; mark is separate.
if grep -q 'onClicked: root.openUrl(modelData.url)' "$panel"; then
  pass "Panel click openUrl"
else
  bad "Panel click openUrl"
fi

if grep -q 'text: "Mark all read"' "$panel"; then
  pass "QML Mark all read control"
else
  bad "QML Mark all read control"
fi
if grep -q 'text: "Mark read"' "$panel" && grep -q 'onClicked: root.openUrl(modelData.url)' "$panel"; then
  pass "QML Mark read control separate from openUrl"
else
  bad "QML Mark read control separate from openUrl"
fi
if python3 - "$panel" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]).read_text()
am = p.find("function applyMark")
apply_m = p[am:p.find("function applyStatus")] if am != -1 else ""
ok = "refreshUnread()" in apply_m and "unreadCount" not in apply_m
ok = ok and "pendingUnread" in p and 'if (unreadProc.running)' in p[p.find("function refreshUnread"):p.find("function checkStatus")]
sys.exit(0 if ok else 1)
PY
then
  pass "QML applyMark refreshUnread no local count"
else
  bad "QML applyMark refreshUnread no local count"
fi
if grep -q 'function markRead' "$panel" && grep -q 'function markAllRead' "$panel" \
   && grep -q 'function openUrl' "$panel"; then
  pass "QML mark functions separate from openUrl"
else
  bad "QML mark functions separate from openUrl"
fi
if grep -q 'enabled: !markReadProc.running' "$panel"; then
  pass "QML Mark read disabled while running"
else
  bad "QML Mark read disabled while running"
fi

if python3 - "$panel" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]).read_text()
opened = p[p.find("onOpenedChanged"):p.find("Process {")]
rn = p.find("function refreshNotifications")
refresh_n = p[rn:p.find("function refresh()", rn)] if rn != -1 else ""
sw = p.find('text: "Notifications"')
switcher = p[sw:p.find("Item {", sw)] if sw != -1 else ""
an = p.find("function applyNotifications")
apply_n = p[an:p.find("onOpenedChanged")] if an != -1 else ""
banned = (
    "markReadProc.running = true",
    "markAllReadProc.running = true",
    '["notifications", "mark-read"',
    '["notifications", "mark-all-read"',
)
ok = all(s not in opened and s not in refresh_n and s not in switcher and s not in apply_n for s in banned)
sys.exit(0 if ok else 1)
PY
then
  pass "QML AC6 no auto-mark"
else
  bad "QML AC6 no auto-mark"
fi

if grep -qE 'markRead|markAllRead' "$bar"; then
  bad "BarWidget mark-read strings"
else
  pass "BarWidget has no mark-read strings"
fi

# --- no secrets committed under tests/ ---------------------------------------

if git -C "$root" ls-files -- 'tests/' | grep -Ei 'api-key|apikey|token|\.env'; then
  bad "tests/ matches gitignore key patterns"
else
  pass "tests/ no key-pattern files"
fi

# Task 2.8: list.sh already invokes unread.sh.
if "$root/tests/list.sh"; then
  pass "tests/list.sh"
else
  bad "tests/list.sh"
fi

[ "$fail" -eq 0 ]
