#!/usr/bin/env bash
#
# Validaciones de contrato para Cloud-Init.
set -euo pipefail

ca_validate_role() {
  case "${CA_ROLE}" in
    frontend|backend-db) ;;
    *) ca_die "Rol no permitido: ${CA_ROLE:-vacio}." ;;
  esac
}

ca_validate_region() {
  [[ "${CA_AWS_REGION}" =~ ^[a-z]{2}-[a-z]+-[0-9]$ ]] || ca_die "Region AWS invalida: ${CA_AWS_REGION}."
}

ca_validate_version() {
  local value="$1"
  local label="$2"
  [[ "${value}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] || ca_die "${label} invalida: ${value}."
}

ca_validate_bucket() {
  local value="$1"
  [[ "${value}" =~ ^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$ ]] || ca_die "Nombre de bucket S3 invalido."
  [[ "${value}" != *".."* ]] || ca_die "Nombre de bucket S3 invalido."
}

ca_validate_s3_key() {
  local value="$1"
  [[ -n "${value}" ]] || ca_die "Clave S3 vacia."
  [[ "${value}" != /* ]] || ca_die "La clave S3 no debe ser absoluta."
  [[ "${value}" != *\\* ]] || ca_die "La clave S3 no debe contener barras invertidas."
  [[ "${value}" != *".."* ]] || ca_die "La clave S3 no debe contener .."
  if [[ "${value}" =~ [[:space:]] ]]; then
    ca_die "La clave S3 no debe contener espacios."
  fi
}

ca_validate_private_ip() {
  local ip="$1"
  [[ "${ip}" =~ ^10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] ||
    [[ "${ip}" =~ ^172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}$ ]] ||
    [[ "${ip}" =~ ^192\.168\.[0-9]{1,3}\.[0-9]{1,3}$ ]] ||
    ca_die "IP privada invalida: ${ip}."
  [[ "${ip}" != 169.254.* ]] || ca_die "No se permite una IP link-local."
}

ca_validate_client_url() {
  local value="$1"
  [[ "${value}" =~ ^https?://[^[:space:]]+$ ]] || ca_die "CLIENT_URL invalida."
  [[ "${value}" != *$'\n'* && "${value}" != *$'\r'* ]] || ca_die "CLIENT_URL contiene saltos de linea."
}

ca_validate_secret_id() {
  local value="$1"
  [[ -n "${value}" ]] || ca_die "SecretId vacio."
  [[ "${value}" != *[[:space:]]* ]] || ca_die "SecretId no debe contener espacios."
  [[ "${value}" != *$'\n'* && "${value}" != *$'\r'* ]] || ca_die "SecretId contiene saltos de linea."
}

ca_validate_flag() {
  local value="$1"
  local label="$2"
  [[ "${value}" == "0" || "${value}" == "1" ]] || ca_die "${label} debe ser 0 o 1."
}

ca_validate_base_env() {
  ca_validate_role
  ca_validate_region
  ca_validate_version "${CA_BUNDLE_VERSION:-}" "BundleVersion"
  ca_validate_bucket "${CA_BUNDLE_BUCKET:-}"
  ca_validate_s3_key "${CA_BUNDLE_KEY:-}"
  ca_validate_sha256_format "${CA_BUNDLE_SHA256:-}" || ca_die "BundleSha256 invalido."
  ca_validate_bucket "${CA_ARTIFACT_BUCKET:-}"
  ca_validate_flag "${CA_RESET_ADMIN_PASSWORD:-0}" "ResetAdminPassword"
  [[ "${CA_TIMEZONE}" == "America/La_Paz" ]] || ca_die "Zona horaria no permitida."
}

ca_validate_frontend_env() {
  ca_validate_base_env
  ca_validate_s3_key "${CA_FRONTEND_ARTIFACT_KEY:-}"
  ca_validate_sha256_format "${CA_FRONTEND_ARTIFACT_SHA256:-}" || ca_die "FrontendArtifactSha256 invalido."
  ca_validate_private_ip "${CA_BACKEND_PRIVATE_IP:-}"
}

ca_validate_backend_env() {
  ca_validate_base_env
  ca_validate_s3_key "${CA_BACKEND_ARTIFACT_KEY:-}"
  ca_validate_sha256_format "${CA_BACKEND_ARTIFACT_SHA256:-}" || ca_die "BackendArtifactSha256 invalido."
  ca_validate_secret_id "${CA_SECRET_ID:-}"
  ca_validate_client_url "${CA_CLIENT_URL:-}"
}
