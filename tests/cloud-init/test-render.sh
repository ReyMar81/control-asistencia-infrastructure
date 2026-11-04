#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ca-render-test.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT

sha="$(make_sha)"
export AWS_REGION="us-east-2"
export BUNDLE_BUCKET="example-control-asistencia-cloud-init"
export BUNDLE_KEY="cloud-init/v0.1.0/bundle.tar.gz"
export BUNDLE_VERSION="v0.1.0"
export BUNDLE_SHA256="${sha}"
export ARTIFACT_BUCKET="example-control-asistencia-artifacts"
export TIMEZONE="America/La_Paz"
export FRONTEND_ARTIFACT_KEY="artifacts/frontend/v0.1.0.tar.gz"
export FRONTEND_ARTIFACT_SHA256="${sha}"
export BACKEND_ARTIFACT_KEY="artifacts/backend/v0.1.0.tar.gz"
export BACKEND_ARTIFACT_SHA256="${sha}"
export BACKEND_PRIVATE_IP="10.0.2.10"
export SECRET_ID="control-asistencia/backend"
export CLIENT_URL="http://localhost:5173"
export RESET_ADMIN_PASSWORD="0"

frontend_out="${tmp}/frontend.sh"
backend_out="${tmp}/backend.sh"
"${REPO_ROOT}/scripts/render-user-data.sh" \
  "${REPO_ROOT}/cloud-init/user-data/frontend.sh.tmpl" "${frontend_out}" >/dev/null
"${REPO_ROOT}/scripts/render-user-data.sh" \
  "${REPO_ROOT}/cloud-init/user-data/backend-db.sh.tmpl" "${backend_out}" >/dev/null

bash -n "${frontend_out}"
bash -n "${backend_out}"
for file in "${frontend_out}" "${backend_out}"; do
  if grep -Eq '__[A-Z0-9_]+__' "${file}"; then
    test_fail "quedaron placeholders en ${file}"
  fi
done

assert_contains "${frontend_out}" 'export CA_ROLE="frontend"'
assert_contains "${frontend_out}" 'export CA_BACKEND_PRIVATE_IP="10.0.2.10"'
assert_contains "${frontend_out}" 'export CA_FRONTEND_ARTIFACT_KEY="artifacts/frontend/v0.1.0.tar.gz"'
assert_not_contains "${frontend_out}" "CA_SECRET_ID"
assert_contains "${backend_out}" 'export CA_ROLE="backend-db"'
assert_contains "${backend_out}" 'export CA_SECRET_ID="control-asistencia/backend"'
assert_contains "${backend_out}" 'export CA_CLIENT_URL="http://localhost:5173"'
assert_contains "${backend_out}" 'export CA_RESET_ADMIN_PASSWORD="0"'

if BUNDLE_SHA256="invalido" "${REPO_ROOT}/scripts/render-user-data.sh" \
  "${REPO_ROOT}/cloud-init/user-data/frontend.sh.tmpl" "${tmp}/bad.sh" >/dev/null 2>&1; then
  test_fail "render acepto un checksum invalido."
fi

if SECRET_ID="" "${REPO_ROOT}/scripts/render-user-data.sh" \
  "${REPO_ROOT}/cloud-init/user-data/backend-db.sh.tmpl" "${tmp}/bad-backend.sh" >/dev/null 2>&1; then
  test_fail "render acepto SECRET_ID vacio."
fi

test_pass "renderizado de user-data"
