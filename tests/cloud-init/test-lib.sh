#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ca-lib-test.XXXXXX")"
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

ca_validate_private_ip "10.0.2.10"
ca_validate_private_ip "172.16.0.5"
ca_validate_private_ip "192.168.1.20"
if ( ca_validate_private_ip "8.8.8.8" ) >/dev/null 2>&1; then
  test_fail "acepto una IP publica."
fi
if ( ca_validate_private_ip "169.254.1.1" ) >/dev/null 2>&1; then
  test_fail "acepto una IP link-local."
fi

printf 'contenido\n' >"${tmp}/checksum.txt"
checksum="$(ca_sha256_file "${tmp}/checksum.txt")"
ca_verify_sha256 "${tmp}/checksum.txt" "${checksum}"
if ( ca_verify_sha256 "${tmp}/checksum.txt" "$(make_sha)" ) >/dev/null 2>&1; then
  test_fail "acepto un checksum incorrecto."
fi

mkdir -p "${tmp}/source/sub"
printf 'hola\n' >"${tmp}/source/sub/file.txt"
tar -czf "${tmp}/good.tar.gz" -C "${tmp}/source" .
mkdir -p "${tmp}/extract"
ca_safe_extract_tar "${tmp}/good.tar.gz" "${tmp}/extract"
assert_file "${tmp}/extract/sub/file.txt"

python_bin="$(command -v python || command -v python3 || true)"
if [[ -n "${python_bin}" ]]; then
  "${python_bin}" - "${tmp}/malicious.tar.gz" "${tmp}/symlink.tar.gz" "${tmp}/absolute.tar.gz" <<'PY'
import io
import sys
import tarfile

malicious, symlink, absolute = sys.argv[1:4]

with tarfile.open(malicious, 'w:gz') as archive:
    info = tarfile.TarInfo('../evil.txt')
    data = b'evil'
    info.size = len(data)
    archive.addfile(info, io.BytesIO(data))

with tarfile.open(symlink, 'w:gz') as archive:
    info = tarfile.TarInfo('link')
    info.type = tarfile.SYMTYPE
    info.linkname = '/etc/passwd'
    archive.addfile(info)

with tarfile.open(absolute, 'w:gz') as archive:
    info = tarfile.TarInfo('/etc/evil.txt')
    data = b'evil'
    info.size = len(data)
    archive.addfile(info, io.BytesIO(data))
PY
  for archive in malicious symlink absolute; do
    if ( ca_safe_extract_tar "${tmp}/${archive}.tar.gz" "${tmp}/out-${archive}" ) >/dev/null 2>&1; then
      test_fail "extract acepto tar ${archive}."
    fi
  done
else
  printf 'SKIP: Python no disponible para tars maliciosos.\n'
fi

cat >"${tmp}/schema.sql" <<'SQL'
CREATE DATABASE control_asistencia;
\connect control_asistencia;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE TABLE example (id bigint);
ALTER TABLE example DROP CONSTRAINT IF EXISTS example_old;
SQL
ca_filter_schema "${tmp}/schema.sql" "${tmp}/schema.filtered.sql"
assert_not_contains "${tmp}/schema.filtered.sql" "CREATE DATABASE"
assert_not_contains "${tmp}/schema.filtered.sql" "\\connect"
assert_contains "${tmp}/schema.filtered.sql" "CREATE EXTENSION"
assert_contains "${tmp}/schema.filtered.sql" "DROP CONSTRAINT"

cat >"${tmp}/dangerous.sql" <<'SQL'
DELETE FROM app_users;
SQL
if ( ca_validate_schema_safety "${tmp}/dangerous.sql" ) >/dev/null 2>&1; then
  test_fail "safety acepto un DELETE."
fi

secret_json='{"DATABASE_URL":"postgres://ca_app:db-pass-123@localhost:5432/control_asistencia","JWT_SECRET":"0123456789abcdef0123456789abcdef","ADMIN_PASSWORD":"admin-password-123"}'
ca_parse_secret_json "${secret_json}"
assert_eq "ca_app" "${CA_DB_USER}" "usuario de base de datos"
assert_eq "db-pass-123" "${CA_DB_PASSWORD}" "password de base de datos"
assert_eq "control_asistencia" "${CA_DB_NAME}" "nombre de base de datos"
assert_eq "localhost" "${CA_DB_HOST}" "host de base de datos"
assert_eq "5432" "${CA_DB_PORT}" "puerto de base de datos"

if ( ca_parse_secret_json '{invalid' ) >/dev/null 2>&1; then
  test_fail "parse acepto JSON invalido."
fi

test_pass "utilidades comunes de Cloud-Init"
