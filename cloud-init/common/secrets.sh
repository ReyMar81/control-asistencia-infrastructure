#!/usr/bin/env bash
#
# Obtencion y parseo de secretos. No imprime valores sensibles.
set -euo pipefail

ca_fetch_secret_json() {
  ca_require_command aws
  aws --version 2>&1 | grep -q 'aws-cli/2\.' || ca_die "Se requiere AWS CLI v2."
  aws secretsmanager get-secret-value \
    --region "${CA_AWS_REGION}" \
    --secret-id "${CA_SECRET_ID}" \
    --query SecretString \
    --output text \
    --no-cli-pager
}

ca_parse_secret_json() {
  local json="$1"
  local out err rc
  out="$(mktemp "${TMPDIR:-/tmp}/ca-secret.XXXXXX")"
  err="$(mktemp "${TMPDIR:-/tmp}/ca-secret-err.XXXXXX")"
  ca_register_tmp_file "${out}"
  ca_register_tmp_file "${err}"

  set +e
  printf '%s' "${json}" | node "${CA_SCRIPT_DIR}/common/parse-secret.mjs" >"${out}" 2>"${err}"
  rc=$?
  set -e
  if (( rc != 0 )); then
    rm -f -- "${out}" "${err}"
    ca_die "No se pudo interpretar el secreto de aplicacion."
  fi

  local -a fields
  mapfile -d '' -t fields <"${out}"
  rm -f -- "${out}" "${err}"
  if (( ${#fields[@]} != 8 )); then
    ca_die "El contrato del secreto no tiene los campos esperados."
  fi

  CA_DATABASE_URL="${fields[0]}"
  CA_JWT_SECRET="${fields[1]}"
  CA_ADMIN_PASSWORD="${fields[2]}"
  CA_DB_USER="${fields[3]}"
  CA_DB_PASSWORD="${fields[4]}"
  CA_DB_HOST="${fields[5]}"
  CA_DB_PORT="${fields[6]}"
  CA_DB_NAME="${fields[7]}"

  [[ "${CA_DB_HOST}" == "localhost" || "${CA_DB_HOST}" == "127.0.0.1" || "${CA_DB_HOST}" == "::1" ]] ||
    ca_die "DATABASE_URL debe usar localhost."
  [[ "${CA_DB_PORT}" == "5432" ]] || ca_die "DATABASE_URL debe usar el puerto 5432."
  [[ "${CA_DB_USER}" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]] || ca_die "Usuario de base de datos invalido."
  [[ "${CA_DB_NAME}" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]] || ca_die "Nombre de base de datos invalido."
  (( ${#CA_JWT_SECRET} >= 32 )) || ca_die "JWT_SECRET debe tener al menos 32 caracteres."
  (( ${#CA_ADMIN_PASSWORD} >= 12 )) || ca_die "ADMIN_PASSWORD debe tener al menos 12 caracteres."
  ca_log "Secreto de aplicacion cargado y validado."
}

ca_load_secret() {
  local secret_json
  secret_json="$(ca_fetch_secret_json)" || ca_die "No se pudo leer el secreto desde Secrets Manager."
  ca_parse_secret_json "${secret_json}"
  unset secret_json
}

ca_write_backend_env() {
  local tmp
  local database_url jwt_secret client_url
  database_url="$(ca_env_quote "${CA_DATABASE_URL}")"
  jwt_secret="$(ca_env_quote "${CA_JWT_SECRET}")"
  client_url="$(ca_env_quote "${CA_CLIENT_URL}")"

  tmp="$(mktemp "${TMPDIR:-/tmp}/ca-backend-env.XXXXXX")"
  ca_register_tmp_file "${tmp}"
  {
    printf 'NODE_ENV="production"\n'
    printf 'PORT="3000"\n'
    printf 'DATABASE_URL=%s\n' "${database_url}"
    printf 'JWT_SECRET=%s\n' "${jwt_secret}"
    printf 'CLIENT_URL=%s\n' "${client_url}"
  } >"${tmp}"
  chmod 0600 "${tmp}"

  ca_install_dir "${CA_ETC_ROOT}" 0750
  install -m 0600 "${tmp}" "${CA_ETC_ROOT}/backend.env"
  ca_chown "${CA_APP_USER}:${CA_APP_GROUP}" "${CA_ETC_ROOT}/backend.env"
  rm -f -- "${tmp}"
  unset database_url jwt_secret client_url
  ca_log "Archivo de entorno del backend escrito con permisos 0600."
}

ca_sql_literal() {
  local value="$1"
  [[ "${value}" != *$'\n'* && "${value}" != *$'\r'* ]] || ca_die "Valor SQL contiene saltos de linea."
  value="${value//\'/\'\'}"
  printf '%s' "${value}"
}

ca_sql_identifier() {
  local value="$1"
  value="${value//\"/\"\"}"
  printf '%s' "${value}"
}
