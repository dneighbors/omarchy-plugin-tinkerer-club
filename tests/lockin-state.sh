#!/usr/bin/env bash
# LockIn state helper tests. No network. No live key.
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

BASE_URL="https://lockin.test.invalid"
run_lockin_state() {
  "$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" lockin state
}

assert_no_key() {
  local label="$1" stdout="$2" stderr="$3"
  case "$stdout$stderr" in
    *"$TEST_KEY"*) bad "$label leaked key" ;;
    *) pass "$label no key leak" ;;
  esac
}

assert_post_lockin_state() {
  local label="$1" log
  log=$(cat "$CURL_LOG")
  case "$log" in
    *"-X POST"*) pass "$label POST" ;;
    *) bad "$label missing -X POST"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"/api/v1/lockIn/state"*) pass "$label lockIn/state URL" ;;
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
  case "$log" in
    *"lockIn/start"*|*"lockIn/finish"*|*"lockIn/createTodo"*|*"lockIn/updateTodo"*|*"lockIn/deleteTodo"*|*"lockIn/todos"*)
      bad "$label called forbidden lockIn procedure"
      printf '  log=%s\n' "$log"
      ;;
    *) pass "$label state only" ;;
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

assert_success_shape() {
  local label="$1" out="$2"
  if printf '%s' "$out" | jq -e '
    .ok == true
    and (has("current"))
    and (.participants | type == "array")
    and (.serverNow | type == "string")
    and (.onboarded | type == "boolean")
  ' >/dev/null 2>&1; then
    pass "$label required keys"
  else
    bad "$label required keys"
    printf '  out=%s\n' "$out"
  fi
}

# --- successful unwrap fixtures ----------------------------------------------

for name in \
  lockin-live \
  lockin-idle \
  lockin-timeout \
  lockin-data-wrapped \
  lockin-participants-array \
  lockin-empty
do
  : > "$CURL_LOG"
  export CURL_BODY="$root/tests/fixtures/${name}.in.json"
  export CURL_CODE=200
  err_file="$work/err.$name"
  rc=0
  out=$(run_lockin_state 2>"$err_file") || rc=$?
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
  assert_success_shape "success $name" "$out"
  assert_post_lockin_state "success $name"
  assert_no_key "success $name" "$out" "$err"
done

# --- 401 auth, mention key file, never the key -------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/lockin-401.in.json"
export CURL_CODE=401
err_file="$work/err.401"
rc=0
out=$(run_lockin_state 2>"$err_file") || rc=$?
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
assert_post_lockin_state "401"
assert_fail_envelope "401" "$out"
assert_no_key "401" "$out" "$err"

# --- missing key file: configured-style error, no curl -----------------------

: > "$CURL_LOG"
unset CURL_BODY
export CURL_CODE=200
missing="$work/missing-key"
err_file="$work/err.missing"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$missing" lockin state 2>"$err_file") || rc=$?
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

# --- unknown lockin subcommand -----------------------------------------------

: > "$CURL_LOG"
err_file="$work/err.unknown"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" lockin frob 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1 \
   && printf '%s' "$out" | grep -q 'frob' \
   && [ ! -s "$CURL_LOG" ]; then
  pass "unknown lockin subcommand"
else
  bad "unknown lockin subcommand"
  printf '  rc=%s out=%s log=%s\n' "$rc" "$out" "$(cat "$CURL_LOG")"
fi
assert_no_key "unknown lockin subcommand" "$out" "$err"

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
  pass "notifications unread still works"
else
  bad "notifications unread still works"
  printf '  rc=%s out=%s\n' "$rc" "$out"
fi
case "$log" in
  *"/api/v1/notification/unreadCount"*) pass "unread hits unreadCount" ;;
  *) bad "unread URL"; printf '  log=%s\n' "$log" ;;
esac
case "$log" in
  *"/api/v1/lockIn/state"*) bad "unread called lockIn/state" ;;
  *) pass "unread did not call lockIn/state" ;;
esac
assert_no_key "notifications unread" "$out" "$err"

# --- usage lists lockin state and todos ----------------------------------------

if "$tinkerer" -h 2>/dev/null | grep -q 'lockin state'; then
  pass "usage lists lockin state"
else
  bad "usage lists lockin state"
fi
if "$tinkerer" -h 2>/dev/null | grep -q 'lockin todos'; then
  pass "usage lists lockin todos"
else
  bad "usage lists lockin todos"
fi

# --- state command must not call todos API -------------------------------------

if python3 - "$tinkerer" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]).read_text()
state = p[p.find("cmd_lockin_state()"):p.find("cmd_lockin_start()")]
for proc in ("lockIn/todos", "lockIn/createTodo", "lockIn/updateTodo", "lockIn/deleteTodo"):
    if proc in state:
        raise SystemExit(1)
raise SystemExit(0)
PY
then
  pass "state helper no todo API"
else
  bad "state helper no todo API"
fi

if grep -q 'lockin)' "$tinkerer" && grep -q 'cmd_lockin_state' "$tinkerer"; then
  pass "lockin dispatch present"
else
  bad "lockin dispatch present"
fi

if grep -q 'unwrap_lockin_state' "$tinkerer"; then
  pass "unwrap_lockin_state present"
else
  bad "unwrap_lockin_state present"
fi

# --- no secrets committed under tests/ -----------------------------------------

if git -C "$root" ls-files -- 'tests/' | grep -Ei 'api-key|apikey|token|\.env'; then
  bad "tests/ matches gitignore key patterns"
else
  pass "tests/ no key-pattern files"
fi

# --- regression: unread.sh must still pass -----------------------------------

if "$root/tests/unread.sh" >/dev/null; then
  pass "unread.sh regression"
else
  bad "unread.sh regression"
fi

[ "$fail" -eq 0 ]
