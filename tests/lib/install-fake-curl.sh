#!/usr/bin/env bash
# Install a curl stub for fixture tests. Requires CURL_LOG in the environment.
set -euo pipefail

work="${1:?work directory required}"
mkdir -p "$work/bin"
cat > "$work/bin/curl" <<'EOS'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CURL_LOG:?}"

output_file=""
write_out=""
skip_next=0
for arg in "$@"; do
  if (( skip_next )); then
    skip_next=0
    continue
  fi
  case "$arg" in
    -o)
      skip_next=1
      continue
      ;;
    -o*)
      output_file="${arg#-o}"
      continue
      ;;
    -w)
      skip_next=1
      continue
      ;;
    --max-time|--max-filesize|--data)
      skip_next=1
      continue
      ;;
    -H|-X|-s|-S)
      skip_next=1
      continue
      ;;
    http://*|https://*)
      ;;
  esac
done

# Re-parse for -o and -w (first pass only set output_file from -o*)
output_file=""
write_out=""
args=("$@")
i=0
while (( i < ${#args[@]} )); do
  case "${args[i]}" in
    -o)
      output_file="${args[i + 1]:-}"
      i=$((i + 2))
      ;;
    -o*)
      output_file="${args[i]#-o}"
      i=$((i + 1))
      ;;
    -w)
      write_out="${args[i + 1]:-}"
      i=$((i + 2))
      ;;
    *)
      i=$((i + 1))
      ;;
  esac
done

if [[ -z "${CURL_BODY:-}" || ! -f "${CURL_BODY}" ]]; then
  exit 1
fi

if [[ -n "${CURL_OVERSIZE_BYTES:-}" && -f "${CURL_BODY}" ]]; then
  oversize="$((CURL_OVERSIZE_BYTES + 1))"
  if [[ "$(wc -c <"${CURL_BODY}" | tr -d ' ')" -ge "$oversize" ]]; then
    if [[ -n "$output_file" && "$output_file" != "-" ]]; then
      head -c "$oversize" "${CURL_BODY}" >"$output_file"
    fi
    if [[ "$write_out" == '%{http_code}' ]]; then
      printf '%s' "${CURL_CODE:-200}"
    fi
    exit 0
  fi
fi

if [[ -n "$output_file" ]]; then
  if [[ "$output_file" == "-" ]]; then
    cat "${CURL_BODY}"
  else
    cat "${CURL_BODY}" >"$output_file"
  fi
else
  cat "${CURL_BODY}"
fi

if [[ "$write_out" == '%{http_code}' ]]; then
  printf '%s' "${CURL_CODE:-200}"
fi
exit 0
EOS
chmod +x "$work/bin/curl"
