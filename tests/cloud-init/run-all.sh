#!/usr/bin/env bash
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for test in \
  "${dir}/test-static.sh" \
  "${dir}/test-render.sh" \
  "${dir}/test-yaml-user-data.sh" \
  "${dir}/test-audit.sh" \
  "${dir}/test-lib.sh" \
  "${dir}/test-integration.sh"; do
  printf '\n== %s ==\n' "$(basename "${test}")"
  bash "${test}"
done

printf '\nTodas las pruebas locales de Cloud-Init pasaron.\n'
