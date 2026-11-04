#!/usr/bin/env bash
#
# Smoke test de solo lectura contra una URL base.
# No despliega ni modifica recursos.
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'Uso: %s <base-url>\n' "$0" >&2
  printf 'Ejemplo: %s http://203.0.113.10\n' "$0" >&2
  exit 2
fi

base_url="${1%/}"

if ! command -v curl >/dev/null 2>&1; then
  printf 'curl no está disponible.\n' >&2
  exit 1
fi

check() {
  local name="$1"
  local url="$2"

  if curl -fsS --max-time 10 -o /dev/null "${url}"; then
    printf 'OK   %s (%s)\n' "${name}" "${url}"
  else
    printf 'FAIL %s (%s)\n' "${name}" "${url}" >&2
    return 1
  fi
}

errors=0
check "frontend healthz" "${base_url}/healthz" || errors=$((errors + 1))
check "backend health" "${base_url}/api/health" || errors=$((errors + 1))

if (( errors > 0 )); then
  exit 1
fi
