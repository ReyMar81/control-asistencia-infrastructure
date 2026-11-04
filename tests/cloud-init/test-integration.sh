#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ca-integration-test.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT

chmod +x "${REPO_ROOT}"/tests/mocks/*

export PATH="${REPO_ROOT}/tests/mocks:${PATH}"
export MOCK_LOG="${tmp}/mock-log"
export MOCK_S3_DIR="${tmp}/s3"
export MOCK_SECRET_FILE="${tmp}/secret.json"
export MOCK_DB_DIR="${tmp}/db-state"
export MOCK_SQL_LOG="${tmp}/sql-log"
mkdir -p "${MOCK_LOG}" "${MOCK_S3_DIR}/artifacts" "${MOCK_DB_DIR}" "${MOCK_SQL_LOG}"

export CA_SCRIPT_DIR="${REPO_ROOT}/cloud-init"
export CA_TEST_MODE="1"
export CA_ROLE=""
export CA_AWS_REGION="us-east-2"
export CA_TIMEZONE="America/La_Paz"
export CA_BUNDLE_VERSION="v0.1.0-test"
export CA_BUNDLE_BUCKET="example-bundle-bucket"
export CA_BUNDLE_KEY="cloud-init/v0.1.0-test/bundle.tar.gz"
export CA_ARTIFACT_BUCKET="example-artifact-bucket"
export CA_FRONTEND_ARTIFACT_KEY="artifacts/frontend.tar.gz"
export CA_BACKEND_ARTIFACT_KEY="artifacts/backend.tar.gz"
export CA_BACKEND_PRIVATE_IP="10.0.2.10"
export CA_SECRET_ID="control-asistencia/backend"
export CA_CLIENT_URL="http://localhost:5173"
export CA_RESET_ADMIN_PASSWORD="0"
export CA_OS_RELEASE_FILE="${tmp}/os-release"
export CA_ARCH="x86_64"
export CA_STATE_ROOT="${tmp}/state"
export CA_LOG_ROOT="${tmp}/log"
export CA_LOG_FILE="${tmp}/log/bootstrap.log"
export CA_LOG_TO_FILE="1"
export CA_OPT_ROOT="${tmp}/opt"
export CA_WWW_ROOT="${tmp}/www"
export CA_ETC_ROOT="${tmp}/etc"
export CA_SYSTEMD_ROOT="${tmp}/systemd"
export CA_NGINX_ROOT="${tmp}/nginx"
export CA_PGDATA_ROOT="${tmp}/pgdata"
export CA_RETRY_COUNT="2"
export CA_RETRY_SLEEP="0"
export CA_APP_USER="controlasistencia"
export CA_APP_GROUP="controlasistencia"

cat >"${CA_OS_RELEASE_FILE}" <<'EOF'
ID=amzn
VERSION_ID=2023
EOF

mkdir -p "${tmp}/frontend-source" "${tmp}/backend-source/src"
printf '{"name":"fixture-frontend","version":"1.0.0"}\n' >"${tmp}/frontend-source/package.json"
printf '{}\n' >"${tmp}/frontend-source/package-lock.json"
tar -czf "${MOCK_S3_DIR}/artifacts/frontend.tar.gz" -C "${tmp}/frontend-source" .

printf '{"name":"fixture-backend","version":"1.0.0","type":"module"}\n' >"${tmp}/backend-source/package.json"
printf '{}\n' >"${tmp}/backend-source/package-lock.json"
printf "console.log('fixture backend');\n" >"${tmp}/backend-source/src/server.js"
cat >"${tmp}/backend-source/schema.sql" <<'SQL'
CREATE DATABASE control_asistencia;
\connect control_asistencia;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE IF NOT EXISTS app_users (id bigint primary key, email text, role text);
INSERT INTO app_users (id, email, role) VALUES (1, 'admin@asistencia.local', 'ADMIN') ON CONFLICT DO NOTHING;
SQL
tar -czf "${MOCK_S3_DIR}/artifacts/backend.tar.gz" -C "${tmp}/backend-source" .

export CA_FRONTEND_ARTIFACT_SHA256
export CA_BACKEND_ARTIFACT_SHA256
CA_FRONTEND_ARTIFACT_SHA256="$(sha256sum "${MOCK_S3_DIR}/artifacts/frontend.tar.gz" | awk '{print $1}')"
CA_BACKEND_ARTIFACT_SHA256="$(sha256sum "${MOCK_S3_DIR}/artifacts/backend.tar.gz" | awk '{print $1}')"
export CA_BUNDLE_SHA256="${CA_FRONTEND_ARTIFACT_SHA256}"

cat >"${MOCK_SECRET_FILE}" <<'EOF'
{"DATABASE_URL":"postgres://ca_app:fixture-db-password@localhost:5432/control_asistencia","JWT_SECRET":"fixture-jwt-secret-0123456789abcdef","ADMIN_PASSWORD":"fixture-admin-password-123"}
EOF

run_bootstrap() {
  local role="$1"
  if ! bash "${REPO_ROOT}/cloud-init/bootstrap.sh" --role "${role}"; then
    cat "${CA_LOG_FILE}" >&2 || true
    test_fail "bootstrap ${role} fallo."
  fi
}

run_bootstrap frontend
assert_file "${CA_STATE_ROOT}/state/frontend/complete"
assert_file "${CA_WWW_ROOT}/current/index.html"
assert_contains "${CA_NGINX_ROOT}/conf.d/control-asistencia.conf" "proxy_pass http://10.0.2.10:3000;"
assert_contains "${CA_LOG_FILE}" "Frontend configurado."
frontend_s3_before="$(count_matches "${MOCK_LOG}/aws.log" 's3 cp')"
frontend_npm_before="$(count_matches "${MOCK_LOG}/npm.log" 'ci')"
assert_eq "1" "${frontend_s3_before}" "descargas S3 frontend"
assert_eq "1" "${frontend_npm_before}" "npm ci frontend"

run_bootstrap frontend
assert_eq "${frontend_s3_before}" "$(count_matches "${MOCK_LOG}/aws.log" 's3 cp')" "S3 frontend idempotente"
assert_eq "${frontend_npm_before}" "$(count_matches "${MOCK_LOG}/npm.log" 'ci')" "npm frontend idempotente"

run_bootstrap backend-db
assert_file "${CA_STATE_ROOT}/state/backend-db/complete"
assert_file "${CA_ETC_ROOT}/backend.env"
assert_file "${CA_SYSTEMD_ROOT}/control-asistencia-backend.service"
assert_file "${MOCK_DB_DIR}/role"
assert_file "${MOCK_DB_DIR}/database"
assert_file "${MOCK_DB_DIR}/extensions"
assert_file "${MOCK_DB_DIR}/admin"
assert_contains "${CA_ETC_ROOT}/backend.env" 'DATABASE_URL="postgres://ca_app:fixture-db-password@localhost:5432/control_asistencia"'
assert_contains "${CA_ETC_ROOT}/backend.env" 'JWT_SECRET="fixture-jwt-secret-0123456789abcdef"'
assert_contains "${CA_SYSTEMD_ROOT}/control-asistencia-backend.service" "src/server.js"
assert_contains "${CA_LOG_FILE}" "Backend y PostgreSQL configurados."

schema_file="$(find "${MOCK_SQL_LOG}" -type f -name '*ca-schema*' | head -n 1)"
[[ -n "${schema_file}" ]] || test_fail "no se aplico schema.sql."
assert_not_contains "${schema_file}" "CREATE DATABASE"
assert_not_contains "${schema_file}" "\\connect"
assert_contains "${schema_file}" "CREATE TABLE"

for secret_value in \
  "fixture-db-password" \
  "fixture-jwt-secret-0123456789abcdef" \
  "fixture-admin-password-123"; do
  assert_not_contains "${CA_LOG_FILE}" "${secret_value}"
done

admin_updates_before="$(grep -Rl 'UPDATE app_users' "${MOCK_SQL_LOG}" | wc -l | tr -d ' ')"
[[ "${admin_updates_before}" -ge 1 ]] || test_fail "no se actualizo la contrasena del administrador."
backend_s3_before="$(count_matches "${MOCK_LOG}/aws.log" 's3 cp')"
backend_npm_before="$(count_matches "${MOCK_LOG}/npm.log" '--omit=dev')"

run_bootstrap backend-db
assert_eq "${backend_s3_before}" "$(count_matches "${MOCK_LOG}/aws.log" 's3 cp')" "S3 backend idempotente"
assert_eq "${backend_npm_before}" "$(count_matches "${MOCK_LOG}/npm.log" '--omit=dev')" "npm backend idempotente"
admin_updates_after="$(grep -Rl 'UPDATE app_users' "${MOCK_SQL_LOG}" | wc -l | tr -d ' ')"
assert_eq "${admin_updates_before}" "${admin_updates_after}" "actualizacion de admin idempotente"

test_pass "integracion local de roles con mocks"
