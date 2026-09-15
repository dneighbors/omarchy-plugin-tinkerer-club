#!/usr/bin/env bash
# LockIn todos helper and QML contract tests. No network. No live key.
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
export TINKERER_TODO_UUID="11111111-1111-4111-8111-111111111111"

BASE_URL="https://lockin-todos.test.invalid"

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

assert_post_todos() {
  local label="$1"
  local log
  log=$(cat "$CURL_LOG")
  case "$log" in
    *"-X POST"*) pass "$label POST" ;;
    *) bad "$label missing -X POST"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"/api/v1/lockIn/todos"*) pass "$label lockIn/todos URL" ;;
    *) bad "$label URL"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"app.tinkerer.club"*) bad "$label hit live origin" ;;
    *) pass "$label no live origin" ;;
  esac
  case "$log" in
    *"--data {}"*|*"--data '{}'"*) pass "$label POST body {}" ;;
    *) bad "$label POST body {}"; printf '  log=%s\n' "$log" ;;
  esac
}

assert_post_create() {
  local label="$1" want_id="$2" want_title="$3"
  local log body
  log=$(cat "$CURL_LOG")
  case "$log" in
    *"/api/v1/lockIn/createTodo"*) pass "$label createTodo URL" ;;
    *) bad "$label createTodo URL"; printf '  log=%s\n' "$log" ;;
  esac
  body=$(printf '%s' "$log" | grep -oE '\{"id":"[^"]*","title":"[^"]*"\}' | head -1 || true)
  if [ -n "$body" ] && printf '%s' "$body" | jq -e --arg id "$want_id" --arg title "$want_title" '.id == $id and .title == $title' >/dev/null 2>&1; then
    pass "$label createTodo body"
  else
    bad "$label createTodo body"
    printf '  body=%s log=%s\n' "$body" "$log"
  fi
}

assert_post_update() {
  local label="$1" want_id="$2" want_completed="$3"
  local log body
  log=$(cat "$CURL_LOG")
  case "$log" in
    *"/api/v1/lockIn/updateTodo"*) pass "$label updateTodo URL" ;;
    *) bad "$label updateTodo URL"; printf '  log=%s\n' "$log" ;;
  esac
  body=$(printf '%s' "$log" | grep -oE '\{"id":"[^"]*","completed":(true|false)\}' | head -1 || true)
  if [ -n "$body" ] && printf '%s' "$body" | jq -e --arg id "$want_id" --argjson completed "$want_completed" '.id == $id and .completed == $completed' >/dev/null 2>&1; then
    pass "$label updateTodo body"
  else
    bad "$label updateTodo body"
    printf '  body=%s log=%s\n' "$body" "$log"
  fi
}

assert_post_delete() {
  local label="$1" want_id="$2"
  local log body
  log=$(cat "$CURL_LOG")
  case "$log" in
    *"/api/v1/lockIn/deleteTodo"*) pass "$label deleteTodo URL" ;;
    *) bad "$label deleteTodo URL"; printf '  log=%s\n' "$log" ;;
  esac
  body=$(printf '%s' "$log" | grep -oE '\{"id":"[^"]*"\}' | head -1 || true)
  if [ -n "$body" ] && printf '%s' "$body" | jq -e --arg id "$want_id" '.id == $id and (keys == ["id"])' >/dev/null 2>&1; then
    pass "$label deleteTodo body"
  else
    bad "$label deleteTodo body"
    printf '  body=%s log=%s\n' "$body" "$log"
  fi
}

# --- lockin todos list ---------------------------------------------------------

for name in lockin-todos-list lockin-todos-empty; do
  : > "$CURL_LOG"
  export CURL_BODY="$root/tests/fixtures/${name}.in.json"
  export CURL_CODE=200
  err_file="$work/err.$name"
  rc=0
  out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" lockin todos 2>"$err_file") || rc=$?
  err=$(cat "$err_file")
  want=$(jq -c . "$root/tests/fixtures/${name}.out.json")
  got=$(printf '%s' "$out" | jq -c .)
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
    pass "todos list $name"
  else
    bad "todos list $name"
    printf '  rc=%s got=%s want=%s\n' "$rc" "$got" "$want"
  fi
  assert_post_todos "todos list $name"
  assert_no_key "todos list $name" "$out" "$err"
done

# --- lockin todo-add -----------------------------------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/lockin-todos-add.in.json"
export CURL_CODE=200
err_file="$work/err.add"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" lockin todo-add Focus task 2>"$err_file") || rc=$?
err=$(cat "$err_file")
want=$(jq -c . "$root/tests/fixtures/lockin-todos-add.out.json")
got=$(printf '%s' "$out" | jq -c .)
if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
  pass "todo-add with title"
else
  bad "todo-add with title"
  printf '  rc=%s got=%s want=%s\n' "$rc" "$got" "$want"
fi
assert_post_create "todo-add with title" "11111111-1111-4111-8111-111111111111" "Focus task"
assert_no_key "todo-add with title" "$out" "$err"

# --- todo-add missing title ----------------------------------------------------

: > "$CURL_LOG"
err_file="$work/err.add-missing"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" lockin todo-add 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1 \
   && [ ! -s "$CURL_LOG" ]; then
  pass "todo-add missing title no curl"
else
  bad "todo-add missing title"
  printf '  rc=%s out=%s log=%s\n' "$rc" "$out" "$(cat "$CURL_LOG")"
fi
assert_fail_envelope "todo-add missing title" "$out"

# --- todo-add truncates title to 200 -------------------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/lockin-todos-add.in.json"
export CURL_CODE=200
long_title=$(python3 - <<'PY'
print("y" * 250)
PY
)
err_file="$work/err.add-trunc"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" lockin todo-add "$long_title" 2>"$err_file") || rc=$?
log=$(cat "$CURL_LOG")
body=$(printf '%s' "$log" | grep -oE '\{"id":"[^"]*","title":"[^"]*"\}' | head -1 || true)
if [ "$rc" -eq 0 ] && printf '%s' "$body" | jq -e '.title | length == 200' >/dev/null 2>&1; then
  pass "todo-add truncates title"
else
  bad "todo-add truncates title"
  printf '  rc=%s body=%s\n' "$rc" "$body"
fi

# --- lockin todo-done ----------------------------------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/lockin-todos-update.in.json"
export CURL_CODE=200
err_file="$work/err.done"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" lockin todo-done a1b2c3d4-e5f6-4789-a012-3456789abcde 2>"$err_file") || rc=$?
err=$(cat "$err_file")
want=$(jq -c . "$root/tests/fixtures/lockin-todos-update.out.json")
got=$(printf '%s' "$out" | jq -c .)
if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
  pass "todo-done"
else
  bad "todo-done"
  printf '  rc=%s got=%s want=%s\n' "$rc" "$got" "$want"
fi
assert_post_update "todo-done" "a1b2c3d4-e5f6-4789-a012-3456789abcde" true
assert_no_key "todo-done" "$out" "$err"

# --- lockin todo-update false --------------------------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/lockin-todos-update.in.json"
export CURL_CODE=200
err_file="$work/err.update-false"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" lockin todo-update a1b2c3d4-e5f6-4789-a012-3456789abcde false 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == true' >/dev/null 2>&1; then
  pass "todo-update false"
else
  bad "todo-update false"
  printf '  rc=%s out=%s\n' "$rc" "$out"
fi
assert_post_update "todo-update false" "a1b2c3d4-e5f6-4789-a012-3456789abcde" false
assert_no_key "todo-update false" "$out" "$err"

# --- lockin todo-delete --------------------------------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/lockin-todos-delete.in.json"
export CURL_CODE=200
err_file="$work/err.delete"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" lockin todo-delete a1b2c3d4-e5f6-4789-a012-3456789abcde 2>"$err_file") || rc=$?
err=$(cat "$err_file")
want=$(jq -c . "$root/tests/fixtures/lockin-todos-delete.out.json")
got=$(printf '%s' "$out" | jq -c .)
if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
  pass "todo-delete"
else
  bad "todo-delete"
  printf '  rc=%s got=%s want=%s\n' "$rc" "$got" "$want"
fi
assert_post_delete "todo-delete" "a1b2c3d4-e5f6-4789-a012-3456789abcde"
assert_no_key "todo-delete" "$out" "$err"

# --- todos 401 -----------------------------------------------------------------

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/lockin-todos-401.in.json"
export CURL_CODE=401
err_file="$work/err.401"
rc=0
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" lockin todos 2>"$err_file") || rc=$?
err=$(cat "$err_file")
if [ "$rc" -eq 0 ] && printf '%s' "$out" | jq -e '.ok == false' >/dev/null 2>&1; then
  pass "todos 401 ok:false"
else
  bad "todos 401 envelope"
  printf '  rc=%s out=%s\n' "$rc" "$out"
fi
assert_fail_envelope "todos 401" "$out"
assert_no_key "todos 401" "$out" "$err"

# --- usage lists todo commands -------------------------------------------------

for cmd in 'lockin todos' 'lockin todo-add' 'lockin todo-done' 'lockin todo-delete'; do
  if "$tinkerer" -h 2>/dev/null | grep -q "$cmd"; then
    pass "usage lists $cmd"
  else
    bad "usage lists $cmd"
  fi
done

# --- helper isolation ----------------------------------------------------------

if python3 - "$tinkerer" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]).read_text()
chunks = {
    "todos": p[p.find("cmd_lockin_todos()"):p.find("cmd_lockin_todo_add()")],
    "add": p[p.find("cmd_lockin_todo_add()"):p.find("cmd_lockin_todo_update()")],
    "update": p[p.find("cmd_lockin_todo_update()"):p.find("cmd_lockin_todo_done()")],
    "delete": p[p.find("cmd_lockin_todo_delete()"):p.find("while [[ $# -gt 0 ]]")],
}
ok = "lockIn/todos" in chunks["todos"] and "createTodo" not in chunks["todos"]
ok = ok and "lockIn/createTodo" in chunks["add"] and "lockIn/todos" not in chunks["add"]
ok = ok and "lockIn/updateTodo" in chunks["update"] and "lockIn/deleteTodo" not in chunks["update"]
ok = ok and "lockIn/deleteTodo" in chunks["delete"] and "lockIn/updateTodo" not in chunks["delete"]
sys.exit(0 if ok else 1)
PY
then
  pass "helper todo commands isolated"
else
  bad "helper todo commands isolated"
fi

# --- QML checklist contract ----------------------------------------------------

if grep -q 'function refreshLockinTodos' "$panel" && grep -q 'id: todosProc' "$panel"; then
  pass "QML todosProc and refresh"
else
  bad "QML todosProc and refresh"
fi

if grep -q 'function lockinTodoAdd' "$panel" && grep -q 'function lockinTodoToggle' "$panel" && grep -q 'function lockinTodoDelete' "$panel"; then
  pass "QML todo mutation functions"
else
  bad "QML todo mutation functions"
fi

if grep -q 'lockinTodos' "$panel" && grep -q 'Checklist' "$panel"; then
  pass "QML checklist UI"
else
  bad "QML checklist UI"
fi

if grep -q 'todoAddProc' "$panel" && grep -q 'todoUpdateProc' "$panel" && grep -q 'todoDeleteProc' "$panel"; then
  pass "QML todo mutation procs"
else
  bad "QML todo mutation procs"
fi

if grep -q '\["lockin", "todos"\]' "$panel"; then
  pass "QML lockin todos command"
else
  bad "QML lockin todos command"
fi

# --- regression ----------------------------------------------------------------

if "$root/tests/lockin-state.sh" >/dev/null && "$root/tests/lockin-session.sh" >/dev/null; then
  pass "lockin-state/session regression"
else
  bad "lockin-state/session regression"
fi

[ "$fail" -eq 0 ]
