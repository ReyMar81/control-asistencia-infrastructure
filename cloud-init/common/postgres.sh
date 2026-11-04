#!/usr/bin/env bash
#
# PostgreSQL 17 local: inicializacion, esquema y usuario administrador.
set -euo pipefail

ca_psql_as_postgres() {
  if [[ "${CA_TEST_MODE}" == "1" ]]; then
    psql -v ON_ERROR_STOP=1 --no-psqlrc "$@"
  else
    runuser -u postgres -- psql -v ON_ERROR_STOP=1 --no-psqlrc "$@"
  fi
}

ca_psql_postgres_scalar() {
  local sql="$1"
  local database="${2:-postgres}"
  ca_psql_as_postgres -d "${database}" -tAc "${sql}"
}

ca_psql_postgres_file() {
  local file="$1"
  local database="${2:-postgres}"
  ca_psql_as_postgres -d "${database}" -f "${file}"
}

ca_pgpass_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/:/\\:/g'
}

ca_make_pgpass() {
  local pgpass
  pgpass="$(mktemp "${TMPDIR:-/tmp}/ca-pgpass.XXXXXX")"
  ca_register_tmp_file "${pgpass}"
  chmod 0600 "${pgpass}"
  ca_chown "${CA_APP_USER}:${CA_APP_GROUP}" "${pgpass}"
  printf '127.0.0.1:5432:%s:%s:%s\n' \
    "$(ca_pgpass_escape "${CA_DB_NAME}")" \
    "$(ca_pgpass_escape "${CA_DB_USER}")" \
    "$(ca_pgpass_escape "${CA_DB_PASSWORD}")" >"${pgpass}"
  printf '%s' "${pgpass}"
}

ca_psql_app() {
  local pgpass
  pgpass="$(ca_make_pgpass)"
  ca_run_as_app_env "/" PGPASSFILE="${pgpass}" psql \
    -v ON_ERROR_STOP=1 --no-psqlrc \
    -h 127.0.0.1 -p 5432 -U "${CA_DB_USER}" -d "${CA_DB_NAME}" "$@"
}

ca_psql_app_scalar() {
  local sql="$1"
  ca_psql_app -tAc "${sql}"
}

ca_psql_app_file() {
  local file="$1"
  ca_psql_app -f "${file}"
}

ca_write_sql_file() {
  local destination="$1"
  local sql="$2"
  umask 077
  printf '%s\n' "${sql}" >"${destination}"
  chmod 0600 "${destination}"
}

ca_init_postgres_cluster() {
  ca_install_dir "${CA_PGDATA_ROOT}" 0700
  ca_chown postgres:postgres "${CA_PGDATA_ROOT}"
  if [[ ! -f "${CA_PGDATA_ROOT}/PG_VERSION" ]]; then
    ca_step "Inicializando cluster PostgreSQL"
    ca_require_command postgresql-setup
    PGDATA="${CA_PGDATA_ROOT}" postgresql-setup --initdb
  else
    ca_log "Cluster PostgreSQL ya inicializado."
  fi
  [[ -f "${CA_PGDATA_ROOT}/PG_VERSION" ]] || ca_die "PostgreSQL no quedo inicializado."
  ca_chown -R postgres:postgres "${CA_PGDATA_ROOT}"
}

ca_configure_postgres_conf() {
  local conf="${CA_PGDATA_ROOT}/postgresql.conf"
  [[ -f "${conf}" ]] || ca_die "No existe ${conf}."
  local block
  block="$(cat <<'EOF'
listen_addresses = 'localhost'
port = 5432
timezone = 'America/La_Paz'
log_timezone = 'America/La_Paz'
password_encryption = 'scram-sha-256'
EOF
)"
  ca_replace_managed_block "${conf}" "# BEGIN control-asistencia" "# END control-asistencia" "${block}"
  ca_chown postgres:postgres "${conf}"
}

ca_write_pg_hba() {
  local target="${CA_PGDATA_ROOT}/pg_hba.conf"
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/ca-pg_hba.XXXXXX")"
  ca_register_tmp_file "${tmp}"
  cat >"${tmp}" <<'EOF'
# Administrado por Control de Asistencia Cloud-Init.
# Solo conexiones locales; el backend usa TCP con SCRAM.
local   all             postgres                                peer
local   all             all                                     scram-sha-256
host    all             all             127.0.0.1/32            scram-sha-256
host    all             all             ::1/128                 scram-sha-256
EOF
  install -m 0600 "${tmp}" "${target}"
  rm -f -- "${tmp}"
  ca_chown postgres:postgres "${target}"
  if grep -Eq '^[^#].*[[:space:]]trust([[:space:]]|$)' "${target}"; then
    ca_die "pg_hba.conf contiene una regla trust."
  fi
}

ca_configure_postgres() {
  ca_init_postgres_cluster
  ca_configure_postgres_conf
  ca_write_pg_hba
  systemctl enable postgresql
  systemctl restart postgresql
  ca_wait_postgres || ca_die "PostgreSQL no acepta conexiones locales tras reiniciar."
}

ca_create_or_update_role() {
  local exists sql_file sql
  exists="$(ca_psql_postgres_scalar "SELECT 1 FROM pg_roles WHERE rolname = '$(ca_sql_literal "${CA_DB_USER}")' LIMIT 1;")"
  sql_file="$(mktemp "${TMPDIR:-/tmp}/ca-role.XXXXXX")"
  ca_register_tmp_file "${sql_file}"
  if [[ "${exists}" == "1" ]]; then
    sql="ALTER ROLE \"$(ca_sql_identifier "${CA_DB_USER}")\" WITH LOGIN PASSWORD '$(ca_sql_literal "${CA_DB_PASSWORD}")' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;"
  else
    sql="CREATE ROLE \"$(ca_sql_identifier "${CA_DB_USER}")\" WITH LOGIN PASSWORD '$(ca_sql_literal "${CA_DB_PASSWORD}")' NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;"
  fi
  ca_write_sql_file "${sql_file}" "${sql}"
  ca_psql_postgres_file "${sql_file}" postgres
  rm -f -- "${sql_file}"
  ca_log "Rol de base de datos sincronizado."
}

ca_create_database() {
  local exists sql_file sql
  exists="$(ca_psql_postgres_scalar "SELECT 1 FROM pg_database WHERE datname = '$(ca_sql_literal "${CA_DB_NAME}")' LIMIT 1;")"
  if [[ "${exists}" != "1" ]]; then
    sql_file="$(mktemp "${TMPDIR:-/tmp}/ca-db.XXXXXX")"
    ca_register_tmp_file "${sql_file}"
    sql="CREATE DATABASE \"$(ca_sql_identifier "${CA_DB_NAME}")\" OWNER \"$(ca_sql_identifier "${CA_DB_USER}")\" ENCODING 'UTF8' TEMPLATE template0;"
    ca_write_sql_file "${sql_file}" "${sql}"
    ca_psql_postgres_file "${sql_file}" postgres
    rm -f -- "${sql_file}"
    ca_log "Base de datos creada."
  else
    ca_log "Base de datos ya existente."
  fi

  sql_file="$(mktemp "${TMPDIR:-/tmp}/ca-db-grant.XXXXXX")"
  ca_register_tmp_file "${sql_file}"
  sql="ALTER DATABASE \"$(ca_sql_identifier "${CA_DB_NAME}")\" OWNER TO \"$(ca_sql_identifier "${CA_DB_USER}")\"; GRANT ALL PRIVILEGES ON DATABASE \"$(ca_sql_identifier "${CA_DB_NAME}")\" TO \"$(ca_sql_identifier "${CA_DB_USER}")\";"
  ca_write_sql_file "${sql_file}" "${sql}"
  ca_psql_postgres_file "${sql_file}" postgres
  rm -f -- "${sql_file}"
}

ca_create_extensions() {
  local sql_file
  sql_file="$(mktemp "${TMPDIR:-/tmp}/ca-extensions.XXXXXX")"
  ca_register_tmp_file "${sql_file}"
  ca_write_sql_file "${sql_file}" \
    "CREATE EXTENSION IF NOT EXISTS citext; CREATE EXTENSION IF NOT EXISTS pgcrypto; CREATE EXTENSION IF NOT EXISTS unaccent;"
  ca_psql_postgres_file "${sql_file}" "${CA_DB_NAME}"
  rm -f -- "${sql_file}"
  ca_log "Extensiones de PostgreSQL verificadas."
}

ca_filter_schema() {
  local source="$1"
  local destination="$2"
  [[ -f "${source}" ]] || ca_die "No se encontro schema.sql en el artefacto."
  awk '
    /^[[:space:]]*[Cc][Rr][Ee][Aa][Tt][Ee][[:space:]]+[Dd][Aa][Tt][Aa][Bb][Aa][Ss][Ee]([[:space:]]|;)/ { next }
    /^[[:space:]]*\\[Cc][Oo][Nn][Nn][Ee][Cc][Tt]([[:space:]]|;)/ { next }
    { print }
  ' "${source}" >"${destination}"
}

ca_validate_schema_safety() {
  local file="$1"
  if grep -inE '^[[:space:]]*(drop[[:space:]]+(database|schema|table|owned|role|user)|truncate([[:space:]]|;)|delete[[:space:]]+from|alter[[:space:]]+system|create[[:space:]]+(role|user)|alter[[:space:]]+(role|user)|set[[:space:]]+role|copy[[:space:]].*program)' "${file}"; then
    ca_die "El esquema contiene instrucciones destructivas o de seguridad no permitidas."
  fi
}

ca_apply_schema() {
  local schema_source="$1"
  local filtered hash marker
  filtered="$(mktemp "${TMPDIR:-/tmp}/ca-schema.XXXXXX")"
  ca_register_tmp_file "${filtered}"
  ca_filter_schema "${schema_source}" "${filtered}"
  ca_validate_schema_safety "${filtered}"
  hash="$(ca_sha256_file "${filtered}")"
  marker="schema-${hash:0:16}"
  if ca_step_done "${marker}" "applied"; then
    ca_log "Esquema ya aplicado para esta version."
    rm -f -- "${filtered}"
    return 0
  fi
  ca_log "Aplicando esquema de aplicacion."
  ca_psql_app_file "${filtered}"
  ca_mark_step "${marker}" "applied"
  rm -f -- "${filtered}"
}

ca_admin_exists() {
  [[ "$(ca_psql_app_scalar "SELECT 1 FROM app_users WHERE email = 'admin@asistencia.local' AND role = 'ADMIN' LIMIT 1;")" == "1" ]]
}

ca_update_admin_password() {
  local reset="${CA_RESET_ADMIN_PASSWORD:-0}"
  if ca_step_done "admin-password" "initialized" && [[ "${reset}" != "1" ]] && ca_admin_exists; then
    ca_log "Contrasena del administrador ya inicializada; se omite."
    return 0
  fi

  ca_step "Sincronizando contrasena inicial del administrador"
  local sql_file password_literal
  password_literal="$(ca_sql_literal "${CA_ADMIN_PASSWORD}")"
  sql_file="$(mktemp "${TMPDIR:-/tmp}/ca-admin.XXXXXX")"
  ca_register_tmp_file "${sql_file}"
  ca_write_sql_file "${sql_file}" "UPDATE app_users SET password_hash = crypt('${password_literal}', gen_salt('bf')) WHERE email = 'admin@asistencia.local' AND role = 'ADMIN';"
  ca_psql_app_file "${sql_file}"
  rm -f -- "${sql_file}"
  ca_admin_exists || ca_die "No existe el administrador en app_users."
  ca_mark_step "admin-password" "initialized"
  ca_log "Contrasena del administrador actualizada desde Secrets Manager."
}

ca_setup_database() {
  local schema_source="$1"
  ca_create_or_update_role
  ca_create_database
  ca_create_extensions
  ca_apply_schema "${schema_source}"
  ca_update_admin_password
}
