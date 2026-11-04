#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT

test_fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

test_pass() {
  printf 'OK: %s\n' "$*"
}

assert_file() {
  [[ -f "$1" ]] || test_fail "falta archivo: $1"
}

assert_dir() {
  [[ -d "$1" ]] || test_fail "falta directorio: $1"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"
  [[ "${actual}" == "${expected}" ]] || test_fail "${label}: esperado [${expected}], obtenido [${actual}]"
}

assert_contains() {
  local file="$1"
  local needle="$2"
  grep -Fq -- "${needle}" "${file}" || test_fail "${file} no contiene: ${needle}"
}

assert_not_contains() {
  local file="$1"
  local needle="$2"
  if grep -Fq -- "${needle}" "${file}"; then
    test_fail "${file} contiene algo no permitido: ${needle}"
  fi
}

assert_mode() {
  local file="$1"
  local expected="$2"
  local actual
  actual="$(stat -c '%a' "${file}" 2>/dev/null || true)"
  [[ -n "${actual}" ]] || return 0
  assert_eq "${expected}" "${actual}" "permisos de ${file}"
}

count_matches() {
  local file="$1"
  local pattern="$2"
  if [[ ! -f "${file}" ]]; then
    printf '0'
    return 0
  fi
  grep -Ec -- "${pattern}" "${file}" || true
}

make_sha() {
  printf 'a%.0s' $(seq 1 64)
}
