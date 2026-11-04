#!/usr/bin/env bash
#
# Preparación y empaquetado del bundle de Cloud-Init.
# Etapa 3A: empaquetado reproducible y cálculo de checksum local.
# No publica en S3 ni modifica AWS en esta etapa.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cloud_init_dir="${repo_root}/cloud-init"

tmp_dir=""
cleanup() {
  if [[ -n "${tmp_dir}" && -d "${tmp_dir}" ]]; then
    rm -rf "${tmp_dir}"
  fi
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Uso:
  publish-cloud-init.sh --package-only [destino.tar.gz]
  publish-cloud-init.sh --info
  publish-cloud-init.sh --help

Modos:
  --package-only   Genera localmente el bundle comprimido y calcula su checksum SHA-256.
  --info           Muestra el estado del empaquetado y los contratos requeridos.
  --upload         No disponible en Etapa 3A (reservado para Etapa 3B con autorización).
EOF
}

package_bundle() {
  local output="${1:-${repo_root}/dist/cloud-init-bundle.tar.gz}"
  local out_dir
  out_dir="$(dirname "${output}")"
  mkdir -p "${out_dir}"

  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/ca-bundle-pack.XXXXXX")"

  # Estructura del bundle a empaquetar
  mkdir -p "${tmp_dir}/bundle/common" "${tmp_dir}/bundle/roles" "${tmp_dir}/bundle/files"

  cp -p "${cloud_init_dir}/bootstrap.sh" "${tmp_dir}/bundle/"
  cp -p "${cloud_init_dir}/common/"*.sh "${tmp_dir}/bundle/common/"
  cp -p "${cloud_init_dir}/common/parse-secret.mjs" "${tmp_dir}/bundle/common/"
  cp -p "${cloud_init_dir}/roles/"*.sh "${tmp_dir}/bundle/roles/"
  cp -p "${cloud_init_dir}/files/"* "${tmp_dir}/bundle/files/"

  # Validar que no hay enlaces simbólicos
  if find "${tmp_dir}/bundle" -type l | grep -q .; then
    printf 'ERROR: El bundle no debe contener enlaces simbólicos.\n' >&2
    exit 1
  fi

  # Crear tar.gz reproducible sin metadatos de usuario local
  tar --sort=name \
      --owner=0 --group=0 --numeric-owner \
      --mtime='2026-01-01 00:00:00Z' \
      -czf "${output}" -C "${tmp_dir}/bundle" .

  local sha
  sha="$(sha256sum "${output}" | awk '{print tolower($1)}')"
  local size
  size="$(wc -c <"${output}" | tr -d ' ')"

  printf 'Bundle empaquetado exitosamente:\n'
  printf '  Archivo:  %s\n' "${output}"
  printf '  Tamaño:   %s bytes\n' "${size}"
  printf '  SHA-256:  %s\n' "${sha}"
}

action="${1:---info}"

case "${action}" in
  --package-only)
    package_bundle "${2:-${repo_root}/dist/cloud-init-bundle.tar.gz}"
    ;;
  --info)
    cat <<'EOF'
Cloud-Init Bundle — Etapa 3A
Implementación funcional local completada.

Contenido del bundle:
  - bootstrap.sh
  - common/ (lib.sh, packages.sh, secrets.sh, postgres.sh, validate.sh, parse-secret.mjs)
  - roles/ (frontend.sh, backend-db.sh)
  - files/ (nginx.conf, nginx-control-asistencia.conf.tmpl, control-asistencia-backend.service.tmpl)

Usa '--package-only [destino.tar.gz]' para generar el archivo y calcular su SHA-256.
La publicación en S3 y despliegue en AWS está bloqueada hasta la Etapa 3B.
EOF
    ;;
  --upload|--execute)
    printf 'BLOQUEADO: La subida a S3 y operaciones en AWS corresponden a la Etapa 3B.\n' >&2
    printf 'No se realizaron llamadas ni modificaciones a AWS.\n' >&2
    exit 1
    ;;
  --help|-h)
    usage
    ;;
  *)
    usage
    exit 2
    ;;
esac
