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

printf 'all tests passed: unread.sh list.sh mark.sh lockin-state.sh lockin-session.sh lockin-todos.sh\n'
