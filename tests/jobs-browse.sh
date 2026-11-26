#!/usr/bin/env bash
# Jobs board (jobs.browse) helper and QML contract tests. No network. No live key.
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

BASE_URL="https://jobs.test.invalid"
run_browse() {
  "$tinkerer" --base-url "$BASE_URL" --key-file "$key_file" "$@" jobs browse
}

assert_post_browse() {
  local label="$1" log
  log=$(cat "$CURL_LOG")
  case "$log" in
    *"-X POST"*) pass "$label POST" ;;
    *) bad "$label missing -X POST"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"$BASE_URL/api/v1/jobs/browse"*) pass "$label browse URL" ;;
    *) bad "$label URL"; printf '  log=%s\n' "$log" ;;
  esac
  case "$log" in
    *"app.tinkerer.club"*) bad "$label hit live origin" ;;
    *) pass "$label no live origin" ;;
  esac
  assert_api_key_via_header_file "$label" "$log" "$TEST_KEY"
  # The API answers HTTP 400 without kind, sort and direction.
  case "$log" in
    *'--data {"kind":"HIRING","query":"","skill":"","sort":"NEWEST","direction":"forward"}'*) pass "$label hiring body" ;;
    *) bad "$label hiring body"; printf '  log=%s\n' "$log" ;;
  esac
}

for name in \
  jobs-empty \
  jobs-several \
  jobs-missing-fields \
  jobs-unsafe-url
do
  : > "$CURL_LOG"
  export CURL_BODY="$root/tests/fixtures/${name}.in.json"
  export CURL_CODE=200
  rc=0
  out=$(run_browse 2>"$work/err") || rc=$?
  err=$(cat "$work/err")
  want=$(jq -c . "$root/tests/fixtures/${name}.out.json")
  got=$(printf '%s' "$out" | jq -c .)
  if [ "$rc" -eq 0 ] && [ "$got" = "$want" ]; then
    pass "success $name"
  else
    bad "success $name"
    printf '  rc=%s\n  got=%s\n  want=%s\n' "$rc" "$got" "$want"
  fi
  assert_post_browse "success $name"
  case "$out$err" in
    *"$TEST_KEY"*) bad "success $name leaked key" ;;
    *) pass "success $name no key leak" ;;
  esac
done

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/jobs-empty.in.json"
export CURL_CODE=200
out=$(run_browse)
if printf '%s' "$out" | jq -e '. == {ok: true, total: 0, jobs: []}' >/dev/null 2>&1; then
  pass "empty board"
else
  bad "empty board"; printf '  out=%s\n' "$out"
fi

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/jobs-several.in.json"
out=$(run_browse)
if printf '%s' "$out" | jq -e '[.jobs[].id] == ["job-new","job-mid","job-old"]' >/dev/null 2>&1; then
  pass "newest first, closed post left out"
else
  bad "newest first, closed post left out"; printf '  out=%s\n' "$out"
fi

out=$(run_browse --limit 2)
if printf '%s' "$out" | jq -e '.ok == true and .total == 4 and (.jobs | length) == 2 and .jobs[0].id == "job-new" and .jobs[1].id == "job-mid"' >/dev/null 2>&1; then
  pass "limit caps the list, total stays the board total"
else
  bad "limit caps the list, total stays the board total"; printf '  out=%s\n' "$out"
fi

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/jobs-unsafe-url.in.json"
out=$(run_browse)
if printf '%s' "$out" | jq -e --arg o "$BASE_URL/" '(.jobs | length) == 9 and (.jobs | all(.url | startswith($o)))
    and (.jobs | map(select(.id == "j-js" or .id == "j-off" or .id == "j-lookalike" or .id == "j-file" or .id == "j-slash" or .id == "j-apply") | .url) | unique) == [$o + "jobs"]' >/dev/null 2>&1; then
  pass "unsafe urls fall back to the jobs page on the configured origin"
else
  bad "unsafe urls fall back to the jobs page on the configured origin"; printf '  out=%s\n' "$out"
fi

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/jobs-400.in.json"
export CURL_CODE=400
out=$(run_browse 2>"$work/err") || true
if printf '%s' "$out" | jq -e '.ok == false and .error == "Tinkerer Club returned HTTP 400." and has("hint") and (has("jobs") | not)' >/dev/null 2>&1; then
  pass "400 error envelope"
else
  bad "400 error envelope"; printf '  out=%s\n' "$out"
fi
case "$out$(cat "$work/err")" in
  *"$TEST_KEY"*) bad "400 leaked key" ;;
  *) pass "400 no key leak" ;;
esac

: > "$CURL_LOG"
export CURL_BODY="$root/tests/fixtures/calendar-401.in.json"
export CURL_CODE=401
out=$(run_browse 2>"$work/err") || true
if printf '%s' "$out" | jq -e '.ok == false and .error == "Authentication failed." and has("hint")' >/dev/null 2>&1; then
  pass "401 auth envelope"
else
  bad "401 auth envelope"; printf '  out=%s\n' "$out"
fi

: > "$CURL_LOG"
out=$("$tinkerer" --base-url "$BASE_URL" --key-file "$work/no-such-key" jobs browse) || true
if printf '%s' "$out" | jq -e '.ok == false and .error == "Add your Tinkerer Club API key." and (.hint | length) > 0' >/dev/null 2>&1 && [ ! -s "$CURL_LOG" ]; then
  pass "no key gives the setup hint without a request"
else
  bad "no key gives the setup hint without a request"; printf '  out=%s\n' "$out"
fi

# --- QML contracts (no QML runner; source assertions) ------------------------

panel="$root/Panel.qml"

grep -q 'id: jobsProc' "$panel" && pass "Panel jobsProc" || bad "Panel jobsProc"
grep -q '"jobs", "browse"' "$panel" && pass "Panel cmd jobs browse" || bad "Panel cmd jobs browse"
grep -q 'function applyJobs' "$panel" && pass "Panel applyJobs" || bad "Panel applyJobs"
grep -q 'label: "Jobs"' "$panel" && pass "Panel Jobs tab" || bad "Panel Jobs tab"
grep -q 'id: jobsFlick' "$panel" && pass "Panel jobs list" || bad "Panel jobs list"
grep -q 'root.plain(root.snippet(modelData.title || "Job post", 90))' "$panel" && pass "Panel job title" || bad "Panel job title"
grep -q 'root.plain(root.jobDetail(modelData))' "$panel" && pass "Panel job company and workplace" || bad "Panel job company and workplace"
grep -q 'root.plain(root.relativeTime(modelData.postedAt))' "$panel" && pass "Panel job age uses the Feed format" || bad "Panel job age uses the Feed format"
grep -q 'onClicked: root.openJob(modelData.url)' "$panel" && pass "Panel job row opens link" || bad "Panel job row opens link"
grep -q 'function jobSafeUrl' "$panel" && pass "Panel checks the link origin" || bad "Panel checks the link origin"
grep -q 'No open job posts.' "$panel" && pass "Panel jobs empty state" || bad "Panel jobs empty state"
grep -q 'root.openUrl(root.jobsPageUrl())' "$panel" && pass "Panel jobs page link" || bad "Panel jobs page link"
grep -q 'root.opened && root.panelView === "jobs"' "$panel" && pass "Panel refresh covers jobs" || bad "Panel refresh covers jobs"

[ "$fail" -eq 0 ]
