#!/usr/bin/env bash
# CI entrypoint: run fixture tests in order; exit on first failure.
set -euo pipefail

root=$(cd "$(dirname -- "$0")" && pwd)

"$root/unread.sh"
"$root/list.sh"
"$root/mark.sh"
"$root/lockin-state.sh"
"$root/lockin-session.sh"
"$root/lockin-todos.sh"
"$root/events-live.sh"
"$root/events-upcoming.sh"
"$root/coworking-calendar.sh"
"$root/tab-row.sh"

printf 'all tests passed: unread.sh list.sh mark.sh lockin-state.sh lockin-session.sh lockin-todos.sh events-live.sh events-upcoming.sh coworking-calendar.sh tab-row.sh\n'
