#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

required=(
  cloud-init/bootstrap.sh
  cloud-init/common/lib.sh
  cloud-init/common/packages.sh
  cloud-init/common/secrets.sh
  cloud-init/common/postgres.sh
  cloud-init/common/validate.sh
  cloud-init/common/parse-secret.mjs
  cloud-init/roles/frontend.sh
  cloud-init/roles/backend-db.sh
  cloud-init/files/nginx.conf
  cloud-init/files/nginx-control-asistencia.conf.tmpl
  cloud-init/files/control-asistencia-backend.service.tmpl
  cloud-init/user-data/frontend.sh.tmpl
  cloud-init/user-data/backend-db.sh.tmpl
  cloud-init/user-data/frontend.yaml.tmpl
  cloud-init/user-data/backend.yaml.tmpl
)

for relative in "${required[@]}"; do
  assert_file "${REPO_ROOT}/${relative}"
done

while IFS= read -r script; do
  bash -n "${script}" || test_fail "sintaxis invalida: ${script}"
done < <(find "${REPO_ROOT}/cloud-init" "${REPO_ROOT}/scripts" "${REPO_ROOT}/tests" -type f \( -name '*.sh' -o -name '*.sh.tmpl' \) | sort)

if command -v shellcheck >/dev/null 2>&1; then
  while IFS= read -r script; do
    shellcheck -S error "${script}" || test_fail "shellcheck fallo: ${script}"
  done < <(find "${REPO_ROOT}/cloud-init" "${REPO_ROOT}/scripts" "${REPO_ROOT}/tests" -type f -name '*.sh' | sort)
else
  printf 'SKIP: shellcheck no disponible.\n'
fi

site="${REPO_ROOT}/cloud-init/files/nginx-control-asistencia.conf.tmpl"
assert_contains "${site}" "__BACKEND_PRIVATE_IP__"
assert_contains "${site}" "proxy_pass http://__BACKEND_PRIVATE_IP__:3000;"
assert_not_contains "${site}" "proxy_pass http://__BACKEND_PRIVATE_IP__:3000/;"
assert_contains "${site}" "location /api/"
assert_contains "${site}" "try_files \$uri \$uri/ /index.html"

unit="${REPO_ROOT}/cloud-init/files/control-asistencia-backend.service.tmpl"
assert_contains "${unit}" "__NODE_BIN__ src/server.js"
assert_contains "${unit}" "EnvironmentFile=__ENV_FILE__"
assert_contains "${unit}" "ProtectSystem=strict"
assert_contains "${unit}" "NoNewPrivileges=true"

pg="${REPO_ROOT}/cloud-init/common/postgres.sh"
assert_contains "${pg}" "listen_addresses = 'localhost'"
assert_contains "${pg}" "port = 5432"
assert_contains "${pg}" "scram-sha-256"

frontend_user_data="${REPO_ROOT}/cloud-init/user-data/frontend.sh.tmpl"
backend_user_data="${REPO_ROOT}/cloud-init/user-data/backend-db.sh.tmpl"
for file in "${frontend_user_data}" "${backend_user_data}"; do
  assert_contains "${file}" "__BUNDLE_SHA256__"
  assert_contains "${file}" "sha256sum"
  assert_not_contains "${file}" "set -x"
done
assert_not_contains "${frontend_user_data}" "CA_SECRET_ID"
assert_contains "${backend_user_data}" "__SECRET_ID__"
assert_contains "${backend_user_data}" "__CLIENT_URL__"

if grep -RInE 'Admin123\*|postgres:postgres@|AKIA[0-9A-Z]{16}' \
  "${REPO_ROOT}/cloud-init" "${REPO_ROOT}/scripts" >/dev/null 2>&1; then
  test_fail "se encontro un secreto o contrasena de ejemplo en scripts."
fi

test_pass "validacion estatica de Cloud-Init"
