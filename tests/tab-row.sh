#!/usr/bin/env bash
# Layout check for the panel's tab row: six tabs (the five shipped plus one
# test-only placeholder) at the default and the smallest panel width must all
# be inside the row, not overlap, keep a readable name, and mark one active.
# Needs Quickshell and the Omarchy shell's QML; skips where they are missing
# (the CI image has neither).
set -euo pipefail

root=$(cd "$(dirname -- "$0")/.." && pwd)
shell_dir=${OMARCHY_SHELL_DIR:-/usr/share/omarchy/shell}

fail() {
  printf 'tab-row.sh: %s\n' "$1" >&2
  [[ -z ${2:-} ]] || printf '%s\n' "$2" >&2
  exit 1
}

# The shipped panel carries the five real views and no placeholders. This
# part needs no shell, so it runs everywhere.
shipped=$(grep -o '{ view: "[a-z]*"' "$root/Panel.qml" | grep -o '"[a-z]*"' | tr -d '"' | paste -sd, -)
[[ $shipped == feed,notifications,events,coworking,lockin ]] ||
  fail "the shipped panel must have exactly the five real tabs, found: $shipped"

if ! command -v quickshell >/dev/null 2>&1 || [[ ! -d $shell_dir/Ui || ! -d $shell_dir/Commons ]]; then
  printf 'tab-row.sh: layout check skipped (needs quickshell and %s)\n' "$shell_dir"
  exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A throwaway shell config: the host's qs.Commons and qs.Ui, the check as the
# entry point, and the panel's TabRow lifted out of Panel.qml into a file of
# its own, so the row under test is the shipped one without starting the
# panel (which would want a window and the member key).
ln -s "$shell_dir/Commons" "$work/Commons"
ln -s "$shell_dir/Ui" "$work/Ui"
mkdir "$work/plugin"
{
  printf 'pragma ComponentBehavior: Bound\nimport QtQuick\nimport qs.Commons\nimport qs.Ui\n'
  awk '/^  component TabRow: Flow \{$/ { print "Flow {"; on = 1; next }
       on && /^  \}$/ { print "}"; exit }
       on { print }' "$root/Panel.qml"
} > "$work/plugin/TabRow.qml"
[[ $(wc -l < "$work/plugin/TabRow.qml") -gt 10 ]] || fail "could not find TabRow in Panel.qml"
cp "$root/tests/qml/TabRowCheck.qml" "$work/shell.qml"

out=$(QT_QPA_PLATFORM=offscreen timeout 30 quickshell -p "$work/shell.qml" 2>&1 || true)
lines=$(printf '%s\n' "$out" | grep -o 'TABROW .*' || true)

[[ $(printf '%s\n' "$lines" | grep -c ' OK$') -eq 2 ]] || fail "expected two passing layouts" "$out"

printf '%s\n' "$lines"
printf 'tab-row.sh: ok\n'
