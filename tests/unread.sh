#!/usr/bin/env bash
# Unread-count helper and QML contract tests. No network. No live key.
set -euo pipefail

root=$(cd "$(dirname -- "$0")/.." && pwd)
tinkerer="$root/bin/tinkerer"
fail=0

pass() { printf 'ok  %s\n' "$1"; }
bad()  { printf 'not ok  %s\n' "$1"; fail=1; }

[ -x "$tinkerer" ] || { echo "missing $tinkerer"; exit 1; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
: > "$work/curl.log"

# Distinctive dummy — must never appear in helper stdout/stderr.
TEST_KEY="test-key-not-real-SECRET99"
key_file="$work/key"
printf '%s\n' "$TEST_KEY" > "$key_file"

cat > "$work/bin/curl" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CURL_LOG:?}"
if [ -n "${CURL_BODY:-}" ] && [ -f "${CURL_BODY}" ]; then
  cat "${CURL_BODY}"
  printf '\n%s' "${CURL_CODE:-200}"
  exit 0
fi
exit 1
EOS
chmod +x "$work/bin/curl"
export CURL_LOG="$work/curl.log"
export PATH="$work/bin:$PATH"

BASE_URL="https://unread.test.invalid"
run_unread() {
  "$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" notifications unread
}

assert_no_key() {
  local label="$1" stdout="$2" stderr="$3"
  case "$stdout$stderr" in
    *"$TEST_KEY"*) bad "$label leaked key" ;;
    *) pass "$label no key leak" ;;
  esac
}

assert_post_unread() {
  local label="$1" log
  log=$(cat "$CURL_LOG")
  case "$log" in
    *"-X POST"*) pass "$label POST" ;;
    *) bad "$label missing -X POST"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"/api/v1/notification/unreadCount"*) pass "$label unreadCount URL" ;;
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
  case "$log" in
    *"x-api-key:"*) pass "$label x-api-key header" ;;
    *) bad "$label x-api-key"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"--data {}"*|*"--data '{}'"*) pass "$label POST body {}" ;;
    *) bad "$label POST body {}"; printf '  log=%s\n' "$log" ;;
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

# --- successful unwrap fixtures ----------------------------------------------

for name in \
  unread-bare-number \
  unread-count-object \
  unread-data-wrapped \
  unread-result-data \
  unread-zero \
  unread-string-count
do
  : > "$CURL_LOG"
  export CURL_BODY="$root/tests/fixtures/${name}.in.json"
  export CURL_CODE=200
  err_file="$work/err.$name"
  rc=0
  out=$(run_unread 2>"$err_file") || rc=$?
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
  if printf '%s' "$got" | jq -e '.count | type == "number"' >/dev/null 2>&1; then
    pass "success $name count is number"
  else
    bad "success $name count is number"
  fi
  assert_post_unread "success $name"
  assert_no_key "success $name" "$out" "$err"
done

# --- extra unwrap shapes from the OpenAPI / tRPC note ------------------------

run_payload() {
  printf '%s' "$1" > "$work/extra.in.json"
  : > "$CURL_LOG"
  export CURL_BODY="$work/extra.in.json"
  export CURL_CODE=200
  run_unread
}

got=$(run_payload '{"unreadCount":3}' | jq -c .)
[ "$got" = '{"ok":true,"count":3}' ] && pass "unwrap unreadCount key" || bad "unwrap unreadCount key ($got)"

got=$(run_payload '{"data":3}' | jq -c .)
[ "$got" = '{"ok":true,"count":3}' ] && pass "unwrap data bare number" || bad "unwrap data bare number ($got)"

got=$(run_payload '{"result":{"data":{"unreadCount":3}}}' | jq -c .)
[ "$got" = '{"ok":true,"count":3}' ] && pass "unwrap result unreadCount" || bad "unwrap result unreadCount ($got)"

got=$(run_payload '{"unread":4}' | jq -c .)
[ "$got" = '{"ok":true,"count":4}' ] && pass "unwrap unread key" || bad "unwrap unread key ($got)"

got=$(run_payload '{"total":5}' | jq -c .)
[ "$got" = '{"ok":true,"count":5}' ] && pass "unwrap total key" || bad "unwrap total key ($got)"

got=$(run_payload '{"count":-2}' | jq -c .)
[ "$got" = '{"ok":true,"count":0}' ] && pass "unwrap negative to 0" || bad "unwrap negative to 0 ($got)"

# --- empty / unusable payload ------------------------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/unread-empty.in.json"
export CURL_CODE=200
err_file="$work/err.empty"
rc=0
out=$(run_unread 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false and (.error | type == "string" and . != "")' >/dev/null 2>&1; then
  pass "empty payload ok:false"
else
  bad "empty payload"
  printf '  rc=%s out=%s\n' "$rc" "$out"
fi
assert_fail_envelope "empty payload" "$out"
assert_no_key "empty payload" "$out" "$err"

# --- 401 auth, mention key file, never the key -------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/unread-401.in.json"
export CURL_CODE=401
err_file="$work/err.401"
rc=0
out=$(run_unread 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "401 ok:false"
else
  bad "401 envelope"
  printf '  rc=%s out=%s\n' "$rc" "$out"
fi
if printf '%s' "$out" | grep -qi 'key file'; then
  pass "401 mentions key file"
else
  bad "401 mentions key file"
  printf '  out=%s\n' "$out"
fi
assert_post_unread "401"
assert_fail_envelope "401" "$out"
assert_no_key "401" "$out" "$err"

# --- 403 same auth envelope as 401 -------------------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/unread-401.in.json"
export CURL_CODE=403
err_file="$work/err.403"
rc=0
out=$(run_unread 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1 \
   && printf '%s' "$out" | grep -qi 'key file'; then
  pass "403 auth envelope"
else
  bad "403 auth envelope"
  printf '  rc=%s out=%s\n' "$rc" "$out"
fi
assert_post_unread "403"
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
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$empty_key" notifications unread 2>"$err_file") || rc=$?
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

# --- curl network failure ----------------------------------------------------

: > "$CURL_LOG"
unset CURL_BODY
export CURL_CODE=200
err_file="$work/err.net"
rc=0
out=$(run_unread 2>"$err_file") || rc=$?
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
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$missing" notifications unread 2>"$err_file") || rc=$?
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

# --- unknown notifications subcommand ----------------------------------------

: > "$CURL_LOG"
err_file="$work/err.unknown"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" notifications frob 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1 \
   && printf '%s' "$out" | grep -q 'frob' \
   && [ ! -s "$CURL_LOG" ]; then
  pass "unknown notifications subcommand"
else
  bad "unknown notifications subcommand"
  printf '  rc=%s out=%s log=%s\n' "$rc" "$out" "$(cat "$CURL_LOG")"
fi
assert_no_key "unknown subcommand" "$out" "$err"

# --- status still configured, never calls unread -----------------------------

: > "$CURL_LOG"
err_file="$work/err.status"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" status 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == true and .configured == true' >/dev/null 2>&1 \
   && [ ! -s "$CURL_LOG" ]; then
  pass "status configured without unread"
else
  bad "status configured without unread"
  printf '  rc=%s out=%s log=%s\n' "$rc" "$out" "$(cat "$CURL_LOG")"
fi
assert_no_key "status" "$out" "$err"

# --- feed dispatch still present; does not call unreadCount ------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/unread-empty.in.json"
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
  *"/api/v1/notification/unreadCount"*) bad "feed called unreadCount" ;;
  *"/api/v1/post/timeline"*) pass "feed still hits timeline" ;;
  *) bad "feed URL"; printf '  log=%s\n' "$log" ;;
esac
assert_no_key "feed" "$out" "$err"

# --- usage names notifications unread only -----------------------------------

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
# Task 2.7: kebab-case mark-read / mark-all-read may appear in usage.
# camelCase markRead / markAllRead stay banned.
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

# --- QML contracts (no QML runner; source assertions) ------------------------

panel="$root/Panel.qml"
bar="$root/BarWidget.qml"

if grep -q 'property int unreadCount: 0' "$panel"; then
  pass "Panel unreadCount"
else
  bad "Panel unreadCount"
fi
if grep -q 'id: unreadProc' "$panel"; then
  pass "Panel unreadProc"
else
  bad "Panel unreadProc"
fi
if grep -q 'notifications", "unread"' "$panel" || grep -q "notifications', 'unread'" "$panel"; then
  pass "Panel cmd notifications unread"
else
  bad "Panel cmd notifications unread"
fi
if grep -q 'function applyUnread' "$panel"; then
  pass "Panel applyUnread"
else
  bad "Panel applyUnread"
fi
if grep -q 'function refreshUnread' "$panel"; then
  pass "Panel refreshUnread"
else
  bad "Panel refreshUnread"
fi
if python3 - "$panel" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]).read_text()
status = p[p.find("function applyStatus"):p.find("function applyFeed")]
feed = p[p.find("function applyFeed"):p.find("function applyUnread")]
ok = "refreshUnread" in status and "configured && !root.opened" in status
ok = ok and "refreshUnread" in feed and "configured && root.opened" in feed
sys.exit(0 if ok else 1)
PY
then
  pass "Panel idle applyStatus refreshUnread"
  pass "Panel applyFeed unread only when open"
else
  bad "Panel idle applyStatus refreshUnread"
  bad "Panel applyFeed unread only when open"
fi
if grep -q 'unreadProc.running' "$panel"; then
  pass "Panel busy includes unreadProc"
else
  bad "Panel busy includes unreadProc"
fi
if grep -q 'id: feedProc' "$panel" && grep -q 'id: statusProc' "$panel" && grep -q 'property bool hasNew\|readonly property bool hasNew' "$panel"; then
  pass "Panel feed/status/hasNew remain"
else
  bad "Panel feed/status/hasNew remain"
fi

if grep -q 'readonly property int unreadCount:' "$bar"; then
  pass "BarWidget unreadCount"
else
  bad "BarWidget unreadCount"
fi
if grep -q '99+' "$bar"; then
  pass "BarWidget 99+ cap"
else
  bad "BarWidget 99+ cap"
fi
if grep -q 'Color.accent' "$bar" && grep -q 'Color.background' "$bar"; then
  pass "BarWidget badge colors"
else
  bad "BarWidget badge colors"
fi
if grep -q 'Text.PlainText' "$bar"; then
  pass "BarWidget PlainText"
else
  bad "BarWidget PlainText"
fi
if grep -q 'Tinkerer Club · ' "$bar" && grep -q ' unread' "$bar"; then
  pass "BarWidget unread tooltip"
else
  bad "BarWidget unread tooltip"
fi
if grep -q '\\ud83e\\udd9e' "$bar"; then
  pass "BarWidget lobster glyph"
else
  bad "BarWidget lobster glyph"
fi
if grep -q 'root.hasNew && !root.opened && root.unreadCount <= 0' "$bar"; then
  pass "BarWidget hasNew hidden while unread pill"
else
  bad "BarWidget hasNew hidden while unread pill"
fi
if grep -q 'visible: root.unreadCount > 0 && !root.opened' "$bar"; then
  pass "BarWidget unread badge idle only"
else
  bad "BarWidget unread badge idle only"
fi
if grep -q 'root.unreadCount > 99 ? "99+" : String(root.unreadCount)' "$bar"; then
  pass "BarWidget badge never literal 0"
else
  bad "BarWidget badge never literal 0"
fi

# --- no secrets committed under tests/ ---------------------------------------

if git -C "$root" ls-files -- 'tests/' | grep -Ei 'api-key|apikey|token|\.env'; then
  bad "tests/ matches gitignore key patterns"
else
  pass "tests/ no key-pattern files"
fi

[ "$fail" -eq 0 ]
