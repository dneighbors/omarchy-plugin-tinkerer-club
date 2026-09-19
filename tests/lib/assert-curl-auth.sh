#!/usr/bin/env bash
# Assert the helper sends x-api-key via a header file, not argv. Requires pass/bad helpers.
assert_api_key_via_header_file() {
  local label="$1" log="$2" test_key="$3"
  case "$log" in
    *"$test_key"*) bad "$label key in argv/log" ;;
    *) pass "$label key not in argv" ;;
  esac
  case "$log" in
    *"-H @"*|*"-H@"*) pass "$label x-api-key header file" ;;
    *) bad "$label x-api-key header file"; printf '  log=%s\n' "$log" ;;
  esac
}
