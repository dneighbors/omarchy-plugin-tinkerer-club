#!/usr/bin/env bash
# Notification-list helper and fixture tests. No network. No live key.
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

BASE_URL="https://list.test.invalid"
run_list() {
  "$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" "$@" notifications list
}

assert_no_key() {
  local label="$1" stdout="$2" stderr="$3"
  case "$stdout$stderr" in
    *"$TEST_KEY"*) bad "$label leaked key" ;;
    *) pass "$label no key leak" ;;
  esac
}

assert_post_list() {
  local label="$1" log body limit
  log=$(cat "$CURL_LOG")
  case "$log" in
    *"-X POST"*) pass "$label POST" ;;
    *) bad "$label missing -X POST"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"/api/v1/notification/list"*) pass "$label list URL" ;;
    *) bad "$label URL"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"app.tinkerer.club"*) bad "$label hit live origin" ;;
    *) pass "$label no live origin" ;;
  esac
  case "$log" in
    *"/api/v1/notification/unreadCount"*|*"notification/markRead"*|*"notification/markAllRead"*)
      bad "$label called unread/mark"
      printf '  log=%s\n' "$log"
      ;;
    *) pass "$label no unread/mark endpoints" ;;
  esac
  case "$log" in
    *"Content-Type: application/json"*) pass "$label Content-Type" ;;
    *) bad "$label Content-Type"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"x-api-key:"*) pass "$label x-api-key header" ;;
    *) bad "$label x-api-key"; printf '  log=%s\n' "$log" ;;
  esac
  body=$(printf '%s' "$log" | grep -oE '\{"limit":[0-9]+\}' | head -1 || true)
  if [ -n "$body" ] && printf '%s' "$body" | jq -e 'has("limit") and (.limit | type == "number")' >/dev/null 2>&1; then
    limit=$(printf '%s' "$body" | jq -r '.limit')
    if [ "$limit" -ge 1 ] && [ "$limit" -le 50 ]; then
      pass "$label POST body limit $limit"
    else
      bad "$label POST body limit out of range ($limit)"
    fi
    if printf '%s' "$body" | jq -e 'keys == ["limit"]' >/dev/null 2>&1; then
      pass "$label POST body limit only"
    else
      bad "$label POST body extra keys"
      printf '  body=%s\n' "$body"
    fi
  else
    bad "$label POST body limit"
    printf '  log=%s\n' "$log"
  fi
  case "$log" in
    *'"cursor"'*|*"cursor="*) bad "$label sent cursor" ;;
    *) pass "$label no cursor" ;;
  esac
}

assert_item_strings() {
  local label="$1" out="$2"
  if printf '%s' "$out" | jq -e '
    .ok == true
    and (.notifications | type == "array")
    and all(.notifications[];
      (.id | type == "string")
      and (.sender | type == "string")
      and (.title | type == "string")
      and (.createdAt | type == "string")
      and (.url | type == "string")
    )
  ' >/dev/null 2>&1; then
    pass "$label string keys"
  else
    bad "$label string keys"
    printf '  out=%s\n' "$out"
  fi
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

assert_limit_body() {
  local label="$1" want="$2" log body
  log=$(cat "$CURL_LOG")
  body=$(printf '%s' "$log" | grep -oE '\{"limit":[0-9]+\}' | head -1 || true)
  if [ "$(printf '%s' "$body" | jq -r '.limit // empty')" = "$want" ]; then
    pass "$label"
  else
    bad "$label"
    printf '  body=%s want=%s log=%s\n' "$body" "$want" "$log"
  fi
}

# --- successful unwrap fixtures ----------------------------------------------

for name in \
  list-items-array \
  list-notifications-key \
  list-data-wrapped \
  list-result-data \
  list-actor-nested \
  list-target-url \
  list-relative-url \
  list-empty \
  list-no-url \
  list-skip-no-id
do
  : > "$CURL_LOG"
  export CURL_BODY="$root/tests/fixtures/${name}.in.json"
  export CURL_CODE=200
  err_file="$work/err.$name"
  rc=0
  out=$(run_list 2>"$err_file") || rc=$?
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
  assert_item_strings "success $name" "$out"
  assert_post_list "success $name"
  assert_no_key "success $name" "$out" "$err"
done

# Task 4.4: relative /posts/abc → https://<test-origin>/posts/abc
rel=$(jq -r '.notifications[0].url' "$root/tests/fixtures/list-relative-url.out.json")
if [ "$rel" = "${BASE_URL}/posts/abc" ]; then
  pass "AC4 relative url joins origin"
else
  bad "AC4 relative url joins origin ($rel)"
fi

# --- extra unwrap shapes -----------------------------------------------------

run_payload() {
  printf '%s' "$1" > "$work/extra.in.json"
  : > "$CURL_LOG"
  export CURL_BODY="$work/extra.in.json"
  export CURL_CODE=200
  run_list
}

got=$(run_payload '{"json":{"items":[{"id":"nj","sender":{"name":"Json"},"title":"Wrapped","createdAt":"2026-09-14T12:00:00.000Z","url":"https://app.tinkerer.club/posts/json"}]}}' | jq -c .)
[ "$got" = '{"ok":true,"notifications":[{"id":"nj","sender":"Json","title":"Wrapped","createdAt":"2026-09-14T12:00:00.000Z","url":"https://app.tinkerer.club/posts/json"}]}' ] \
  && pass "unwrap json wrapper" || bad "unwrap json wrapper ($got)"

got=$(run_payload '{"items":[{"notificationId":"nid","sender":{"name":"Id"},"title":"Alt id","createdAt":"2026-09-14T12:00:00.000Z"}]}' | jq -c .)
[ "$got" = '{"ok":true,"notifications":[{"id":"nid","sender":"Id","title":"Alt id","createdAt":"2026-09-14T12:00:00.000Z","url":""}]}' ] \
  && pass "unwrap notificationId" || bad "unwrap notificationId ($got)"

got=$(run_payload '{"ok":false,"error":"upstream","hint":""}' | jq -c .)
[ "$got" = '{"ok":false,"error":"upstream","hint":""}' ] \
  && pass "pass-through ok:false" || bad "pass-through ok:false ($got)"

# Task 4.4 / Dev Notes: javascript: and file: must become ""
got=$(run_payload '[{"id":"js","sender":{"name":"X"},"title":"Bad","createdAt":"2026-09-14T12:00:00.000Z","url":"javascript:alert(1)"}]' | jq -r '.notifications[0].url')
[ "$got" = "" ] && pass "javascript url empty" || bad "javascript url empty ($got)"

got=$(run_payload '[{"id":"fl","sender":{"name":"X"},"title":"Bad","createdAt":"2026-09-14T12:00:00.000Z","url":"file:///etc/passwd"}]' | jq -r '.notifications[0].url')
[ "$got" = "" ] && pass "file url empty" || bad "file url empty ($got)"

# --- empty / unusable payload → success empty list ---------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/list-unusable.in.json"
export CURL_CODE=200
err_file="$work/err.unusable"
rc=0
out=$(run_list 2>"$err_file") || rc=$?
err=$(cat "$err_file")
got=$(printf '%s' "$out" | jq -c .)
if [ "$rc" -eq 0 ] && [ "$got" = '{"ok":true,"notifications":[]}' ]; then
  pass "unusable payload empty list"
else
  bad "unusable payload"
  printf '  rc=%s out=%s\n' "$rc" "$out"
fi
assert_item_strings "unusable payload" "$out"
assert_post_list "unusable payload"
assert_no_key "unusable payload" "$out" "$err"

# --- 401 auth, mention key file, never the key -------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/list-401.in.json"
export CURL_CODE=401
err_file="$work/err.401"
rc=0
out=$(run_list 2>"$err_file") || rc=$?
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
assert_post_list "401"
assert_fail_envelope "401" "$out"
assert_no_key "401" "$out" "$err"

# --- 403 same auth envelope as 401 -------------------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/list-401.in.json"
export CURL_CODE=403
err_file="$work/err.403"
rc=0
out=$(run_list 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1 \
   && printf '%s' "$out" | grep -qi 'key file'; then
  pass "403 auth envelope"
else
  bad "403 auth envelope"
  printf '  rc=%s out=%s\n' "$rc" "$out"
fi
assert_post_list "403"
assert_fail_envelope "403" "$out"
assert_no_key "403" "$out" "$err"

# --- non-JSON payload --------------------------------------------------------

printf 'not-json\n' > "$work/nonjson.in"
: > "$CURL_LOG"
export CURL_BODY="$work/nonjson.in"
export CURL_CODE=200
err_file="$work/err.nonjson"
rc=0
out=$(run_list 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1 \
   && printf '%s' "$out" | grep -qi 'json'; then
  pass "non-JSON payload ok:false"
else
  bad "non-JSON payload"
  printf '  rc=%s out=%s\n' "$rc" "$out"
fi
assert_fail_envelope "non-JSON payload" "$out"
assert_no_key "non-JSON payload" "$out" "$err"

# --- empty key file: no curl, empty-file error -------------------------------

: > "$CURL_LOG"
unset CURL_BODY
export CURL_CODE=200
empty_key="$work/empty-key"
: > "$empty_key"
err_file="$work/err.emptykey"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$empty_key" notifications list 2>"$err_file") || rc=$?
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
out=$(run_list 2>"$err_file") || rc=$?
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
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$missing" notifications list 2>"$err_file") || rc=$?
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

# --- status still configured, never calls list -------------------------------

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
  *"/api/v1/notification/list"*|*"notification/unreadCount"*|*"notification/markRead"*)
    bad "feed called notification endpoints"
    printf '  log=%s\n' "$log"
    ;;
  *"/api/v1/post/timeline"*) pass "feed still hits timeline" ;;
  *) bad "feed URL"; printf '  log=%s\n' "$log" ;;
esac
assert_no_key "feed" "$out" "$err"

# --- clamp --limit 0 → 1 and --limit 99 → 50 ---------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/list-empty.in.json"
export CURL_CODE=200
err_file="$work/err.limit0"
rc=0
out=$(run_list --limit 0 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == true' >/dev/null 2>&1; then
  pass "limit 0 runs"
else
  bad "limit 0 runs"
  printf '  rc=%s out=%s\n' "$rc" "$out"
fi
assert_limit_body "limit 0 posts 1" 1
assert_post_list "limit 0"
assert_no_key "limit 0" "$out" "$err"

: > "$CURL_LOG"
err_file="$work/err.limit99"
rc=0
out=$(run_list --limit 99 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == true' >/dev/null 2>&1; then
  pass "limit 99 runs"
else
  bad "limit 99 runs"
  printf '  rc=%s out=%s\n' "$rc" "$out"
fi
assert_limit_body "limit 99 posts 50" 50
assert_post_list "limit 99"
assert_no_key "limit 99" "$out" "$err"

# --- usage names list + unread; kebab mark-read may appear (Task 2.7) --------

if "$tinkerer" -h 2>/dev/null | grep -q 'notifications list'; then
  pass "usage lists notifications list"
else
  bad "usage lists notifications list"
fi
if "$tinkerer" -h 2>/dev/null | grep -q 'notifications unread'; then
  pass "usage lists notifications unread"
else
  bad "usage lists notifications unread"
fi
# Helper contains notification/markRead; usage may list kebab-case mark-*.
# camelCase markRead / markAllRead stay unknown commands (not usage lines).
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

panel="$root/Panel.qml"
bar="$root/BarWidget.qml"

if grep -q 'property string panelView: "feed"' "$panel"; then
  pass "Panel panelView default feed"
else
  bad "Panel panelView default feed"
fi
if grep -q 'id: listProc' "$panel" && grep -q 'notifications", "list"' "$panel"; then
  pass "Panel listProc"
else
  bad "Panel listProc"
fi
if grep -q 'property var notifications: \[\]' "$panel"; then
  pass "Panel notifications model"
else
  bad "Panel notifications model"
fi
if grep -q 'text: "Feed"' "$panel" && grep -q 'text: "Notifications"' "$panel"; then
  pass "Panel Feed|Notifications switcher"
else
  bad "Panel Feed|Notifications switcher"
fi
if grep -q 'relativeTime(modelData.createdAt)' "$panel" && grep -q 'modelData.sender' "$panel"; then
  pass "Panel sender/title/relativeTime"
else
  bad "Panel sender/title/relativeTime"
fi
if grep -q 'onClicked: root.openUrl(modelData.url)' "$panel"; then
  pass "Panel click openUrl"
else
  bad "Panel click openUrl"
fi
if grep -q 'No notifications yet.' "$panel"; then
  pass "Panel empty notifications copy"
else
  bad "Panel empty notifications copy"
fi
# Task 2.7: BarWidget stays mark-free. Opening/list must not start mark procs.
if grep -qE 'markRead|markAllRead' "$bar"; then
  bad "BarWidget mark-read strings"
else
  pass "BarWidget has no mark-read strings"
fi
if python3 - "$panel" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]).read_text()
opened = p[p.find("onOpenedChanged"):p.find("Process {")]
rn = p.find("function refreshNotifications")
refresh_n = p[rn:p.find("function refresh()", rn)] if rn != -1 else ""
an = p.find("function applyNotifications")
apply_n = p[an:p.find("onOpenedChanged")] if an != -1 else ""
banned = (
    "markReadProc.running = true",
    "markAllReadProc.running = true",
    '["notifications", "mark-read"',
    '["notifications", "mark-all-read"',
)
ok = all(s not in opened and s not in refresh_n and s not in apply_n for s in banned)
sys.exit(0 if ok else 1)
PY
then
  pass "Panel list path does not start mark procs"
else
  bad "Panel list path does not start mark procs"
fi
if grep -q 'property int unreadCount: 0' "$panel" && grep -q 'function refreshUnread' "$panel"; then
  pass "Panel unread contract remains"
else
  bad "Panel unread contract remains"
fi
if python3 - "$panel" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]).read_text()
timer = p[p.find("Timer {"):p.find("KeyboardPanel")]
opened = p[p.find("onOpenedChanged"):p.find("Process {")]
refresh_n = p[p.find("function refreshNotifications"):p.find("function refresh()")]
refresh = p[p.find("function refresh()"):p.find("function refreshUnread")]
feed = p[p.find("function applyFeed"):p.find("function applyUnread")]
unread = p[p.find("function applyUnread"):p.find("function applyNotifications")]
ok = "refreshFeed()" in timer and "refreshUnread()" in timer and "refreshNotifications" not in timer
ok = ok and "refreshFeed()" in opened and 'panelView = "feed"' in opened
ok = ok and "if (!root.opened)" in refresh_n
ok = ok and "opened && root.panelView === \"notifications\"" in refresh
ok = ok and "panelView === \"feed\"" in feed
ok = ok and unread.count("unreadCount") >= 1 and "unreadCount" not in p[p.find("function applyNotifications"):p.find("onOpenedChanged")]
sys.exit(0 if ok else 1)
PY
then
  pass "Panel AC6 view isolation"
else
  bad "Panel AC6 view isolation"
fi
if grep -q 'property bool viewBusy' "$panel"; then
  pass "Panel viewBusy Refresh"
else
  bad "Panel viewBusy Refresh"
fi

# --- no secrets committed under tests/ ---------------------------------------

if git -C "$root" ls-files -- 'tests/' | grep -Ei 'api-key|apikey|token|\.env'; then
  bad "tests/ matches gitignore key patterns"
else
  pass "tests/ no key-pattern files"
fi

if "$root/tests/unread.sh"; then
  pass "tests/unread.sh"
else
  bad "tests/unread.sh"
fi

[ "$fail" -eq 0 ]
