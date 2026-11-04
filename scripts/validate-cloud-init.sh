#!/usr/bin/env bash
#
# Validaciones estáticas de Cloud-Init. No ejecuta scripts ni modifica AWS.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
errors=0

check_file() {
  local path="$1"
  if [[ ! -f "${path}" ]]; then
    printf 'Falta archivo requerido: %s\n' "${path}" >&2
    errors=$((errors + 1))
  fi
}

check_contains() {
  local path="$1"
  local token="$2"
  if [[ ! -f "${path}" ]]; then
    return
  fi
  if ! grep -q -- "${token}" "${path}"; then
    printf 'Falta token %s en %s\n' "${token}" "${path}" >&2
    errors=$((errors + 1))
  fi
}

for relative in \
  bootstrap.sh \
  common/lib.sh \
  common/packages.sh \
  common/secrets.sh \
  common/validate.sh \
  roles/frontend.sh \
  roles/backend-db.sh \
  files/nginx-control-asistencia.conf.tmpl \
  files/control-asistencia-backend.service.tmpl \
  user-data/frontend.sh.tmpl \
  user-data/backend-db.sh.tmpl \
  user-data/frontend.yaml.tmpl \
  user-data/backend.yaml.tmpl; do
  check_file "${repo_root}/cloud-init/${relative}"
done

check_contains "${repo_root}/cloud-init/files/nginx-control-asistencia.conf.tmpl" "__BACKEND_PRIVATE_IP__"
check_contains "${repo_root}/cloud-init/files/nginx-control-asistencia.conf.tmpl" "location /api/"
check_contains "${repo_root}/cloud-init/files/control-asistencia-backend.service.tmpl" "__TIMEZONE__"
check_contains "${repo_root}/cloud-init/user-data/frontend.sh.tmpl" "__BACKEND_PRIVATE_IP__"
check_contains "${repo_root}/cloud-init/user-data/backend-db.sh.tmpl" "__SECRET_ID__"

for yaml_tmpl in "${repo_root}/cloud-init/user-data/frontend.yaml.tmpl" "${repo_root}/cloud-init/user-data/backend.yaml.tmpl"; do
  check_contains "${yaml_tmpl}" "#cloud-config"
  check_contains "${yaml_tmpl}" "packages:"
  check_contains "${yaml_tmpl}" "write_files:"
  check_contains "${yaml_tmpl}" "runcmd:"
done

while IFS= read -r -d '' script; do
  if ! bash -n "${script}"; then
    printf 'Error de sintaxis: %s\n' "${script}" >&2
    errors=$((errors + 1))
  fi
done < <(find "${repo_root}/cloud-init" "${repo_root}/scripts" "${repo_root}/tests" -type f \( -name '*.sh' -o -name '*.sh.tmpl' \) -print0)

if (( errors > 0 )); then
  printf 'Validación de Cloud-Init falló con %d error(es).\n' "${errors}" >&2
  exit 1
fi

printf 'Validación estática de Cloud-Init: OK\n'
