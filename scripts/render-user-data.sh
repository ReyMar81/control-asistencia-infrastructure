#!/usr/bin/env bash
#
# Renderiza plantillas de user-data (YAML o Shell) sustituyendo tokens.
# Compatible con la demostración Cloud-Init YAML (Etapa 3A-R) y plantillas heredadas.
set -euo pipefail

usage() {
  cat <<'EOF'
Uso:
  render-user-data.sh <plantilla> [salida]

Plantillas YAML Cloud-Init (Etapa 3A-R):
  - frontend.yaml.tmpl:
      BACKEND_PRIVATE_IP (requerida)
      FRONTEND_REPO_URL (opcional, defecto: https://github.com/ReyMar81/frontend-control-asistencia.git)
      GIT_BRANCH (opcional, defecto: main)

  - backend.yaml.tmpl:
      BACKEND_REPO_URL (opcional, defecto: https://github.com/ReyMar81/backend-control-asistencia.git)
      GIT_BRANCH (opcional, defecto: main)
      DB_USER (opcional, defecto: ca_app)
      DB_PASSWORD (opcional, defecto: ControlAsistencia2026*)
      DB_NAME (opcional, defecto: control_asistencia)
      JWT_SECRET (opcional, defecto: super-secret-jwt-token-control-asistencia-2026)
      CLIENT_URL (opcional, defecto: http://localhost:5173)
      PORT (opcional, defecto: 3000)

Plantillas Shell Bundle (Etapa 3A):
  - Variables requeridas: AWS_REGION, BUNDLE_BUCKET, BUNDLE_KEY, BUNDLE_VERSION,
    BUNDLE_SHA256, ARTIFACT_BUCKET, TIMEZONE, etc.
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 2
fi

template="$1"
output="${2:-}"

[[ -f "${template}" ]] || { printf 'Plantilla no encontrada: %s\n' "${template}" >&2; exit 1; }

template_name="$(basename "${template}")"
tmp="$(mktemp "${TMPDIR:-/tmp}/ca-user-data.XXXXXX")"
trap 'rm -f "${tmp}"' EXIT
sed_args=()

add_replacement() {
  local token="$1"
  local value="$2"
  value="${value//\\/\\\\}"
  value="${value//&/\\&}"
  value="${value//|/\\|}"
  sed_args+=(-e "s|${token}|${value}|g")
}

if [[ "${template_name}" == *.yaml.tmpl ]]; then
  # Modo YAML Cloud-Init académico (Etapa 3A-R)
  GIT_BRANCH="${GIT_BRANCH:-main}"
  BACKEND_REPO_URL="${BACKEND_REPO_URL:-https://github.com/ReyMar81/backend-control-asistencia.git}"
  FRONTEND_REPO_URL="${FRONTEND_REPO_URL:-https://github.com/ReyMar81/frontend-control-asistencia.git}"
  DB_USER="${DB_USER:-ca_app}"
  DB_PASSWORD="${DB_PASSWORD:-ControlAsistencia2026*}"
  DB_NAME="${DB_NAME:-control_asistencia}"
  JWT_SECRET="${JWT_SECRET:-super-secret-jwt-token-control-asistencia-2026}"
  CLIENT_URL="${CLIENT_URL:-http://localhost:5173}"
  PORT="${PORT:-3000}"

  if [[ "${template_name}" == "frontend.yaml.tmpl" ]]; then
    if [[ -z "${BACKEND_PRIVATE_IP:-}" ]]; then
      printf 'Variable requerida no definida para frontend: BACKEND_PRIVATE_IP\n' >&2
      exit 1
    fi
    add_replacement '\${BACKEND_PRIVATE_IP}' "${BACKEND_PRIVATE_IP}"
    add_replacement '__BACKEND_PRIVATE_IP__' "${BACKEND_PRIVATE_IP}"
    add_replacement '\${FRONTEND_REPO_URL}' "${FRONTEND_REPO_URL}"
    add_replacement '__FRONTEND_REPO_URL__' "${FRONTEND_REPO_URL}"
    add_replacement '\${GIT_BRANCH}' "${GIT_BRANCH}"
    add_replacement '__GIT_BRANCH__' "${GIT_BRANCH}"
  elif [[ "${template_name}" == "backend.yaml.tmpl" ]]; then
    add_replacement '\${BACKEND_REPO_URL}' "${BACKEND_REPO_URL}"
    add_replacement '__BACKEND_REPO_URL__' "${BACKEND_REPO_URL}"
    add_replacement '\${GIT_BRANCH}' "${GIT_BRANCH}"
    add_replacement '__GIT_BRANCH__' "${GIT_BRANCH}"
    add_replacement '\${DB_USER}' "${DB_USER}"
    add_replacement '__DB_USER__' "${DB_USER}"
    add_replacement '\${DB_PASSWORD}' "${DB_PASSWORD}"
    add_replacement '__DB_PASSWORD__' "${DB_PASSWORD}"
    add_replacement '\${DB_NAME}' "${DB_NAME}"
    add_replacement '__DB_NAME__' "${DB_NAME}"
    add_replacement '\${JWT_SECRET}' "${JWT_SECRET}"
    add_replacement '__JWT_SECRET__' "${JWT_SECRET}"
    add_replacement '\${CLIENT_URL}' "${CLIENT_URL}"
    add_replacement '__CLIENT_URL__' "${CLIENT_URL}"
    add_replacement '\${PORT}' "${PORT}"
    add_replacement '__PORT__' "${PORT}"
  fi

  sed "${sed_args[@]}" "${template}" >"${tmp}"

  # Verificar si quedaron variables sin sustituir
  if grep -Eq '\$\{[A-Z0-9_]+\}|__[A-Z0-9_]+__' "${tmp}"; then
    printf 'Quedaron placeholders sin sustituir en el YAML Cloud-Init.\n' >&2
    exit 1
  fi

else
  # Modo plantillas Shell (Etapa 3A bundle)
  required=(
    AWS_REGION
    BUNDLE_BUCKET
    BUNDLE_KEY
    BUNDLE_VERSION
    BUNDLE_SHA256
    ARTIFACT_BUCKET
    TIMEZONE
  )

  case "${template_name}" in
    frontend.sh.tmpl)
      required+=(FRONTEND_ARTIFACT_KEY FRONTEND_ARTIFACT_SHA256 BACKEND_PRIVATE_IP)
      ;;
    backend-db.sh.tmpl)
      required+=(BACKEND_ARTIFACT_KEY BACKEND_ARTIFACT_SHA256 SECRET_ID CLIENT_URL)
      ;;
  esac

  for name in "${required[@]}"; do
    if [[ -z "${!name:-}" ]]; then
      printf 'Variable requerida no definida: %s\n' "${name}" >&2
      exit 1
    fi
  done

  for name in BUNDLE_SHA256 FRONTEND_ARTIFACT_SHA256 BACKEND_ARTIFACT_SHA256; do
    value="${!name:-}"
    if [[ -n "${value}" && ! "${value}" =~ ^[a-fA-F0-9]{64}$ ]]; then
      printf '%s debe ser un SHA-256 hexadecimal de 64 caracteres.\n' "${name}" >&2
      exit 1
    fi
  done

  [[ "${BUNDLE_VERSION}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] ||
    { printf 'BUNDLE_VERSION invalida.\n' >&2; exit 1; }
  [[ "${TIMEZONE}" == "America/La_Paz" ]] ||
    { printf 'TIMEZONE debe ser America/La_Paz.\n' >&2; exit 1; }
  [[ -z "${BACKEND_PRIVATE_IP:-}" || "${BACKEND_PRIVATE_IP}" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.) ]] ||
    { printf 'BACKEND_PRIVATE_IP debe ser privada.\n' >&2; exit 1; }
  [[ -z "${CLIENT_URL:-}" || "${CLIENT_URL}" =~ ^https?://[^[:space:]]+$ ]] ||
    { printf 'CLIENT_URL invalida.\n' >&2; exit 1; }

  add_token() {
    local token="$1"
    local name="$2"
    add_replacement "${token}" "${!name:-}"
  }

  add_token "__AWS_REGION__" AWS_REGION
  add_token "__TIMEZONE__" TIMEZONE
  add_token "__BUNDLE_BUCKET__" BUNDLE_BUCKET
  add_token "__BUNDLE_KEY__" BUNDLE_KEY
  add_token "__BUNDLE_VERSION__" BUNDLE_VERSION
  add_token "__BUNDLE_SHA256__" BUNDLE_SHA256
  add_token "__ARTIFACT_BUCKET__" ARTIFACT_BUCKET
  add_token "__FRONTEND_ARTIFACT_KEY__" FRONTEND_ARTIFACT_KEY
  add_token "__FRONTEND_ARTIFACT_SHA256__" FRONTEND_ARTIFACT_SHA256
  add_token "__BACKEND_ARTIFACT_KEY__" BACKEND_ARTIFACT_KEY
  add_token "__BACKEND_ARTIFACT_SHA256__" BACKEND_ARTIFACT_SHA256
  add_token "__BACKEND_PRIVATE_IP__" BACKEND_PRIVATE_IP
  add_token "__SECRET_ID__" SECRET_ID
  add_token "__CLIENT_URL__" CLIENT_URL
  RESET_ADMIN_PASSWORD="${RESET_ADMIN_PASSWORD:-0}"
  add_replacement "__RESET_ADMIN_PASSWORD__" "${RESET_ADMIN_PASSWORD}"

  sed "${sed_args[@]}" "${template}" >"${tmp}"

  if grep -Eq '__[A-Z0-9_]+__' "${tmp}"; then
    printf 'Quedaron placeholders sin sustituir en la user-data.\n' >&2
    exit 1
  fi
fi

umask 077
if [[ -n "${output}" ]]; then
  install -D -m 0600 "${tmp}" "${output}"
  printf 'User-data renderizada en %s\n' "${output}"
else
  cat "${tmp}"
fi
