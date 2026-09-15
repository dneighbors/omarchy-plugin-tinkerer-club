#!/usr/bin/env bash
# CI entrypoint: run fixture tests in order; exit on first failure.
set -euo pipefail

root=$(cd "$(dirname -- "$0")" && pwd)

"$root/unread.sh"
"$root/list.sh"
"$root/mark.sh"

printf 'all tests passed: unread.sh list.sh mark.sh\n'
