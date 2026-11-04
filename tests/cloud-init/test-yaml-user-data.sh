#!/usr/bin/env bash
#
# Prueba de validación de las plantillas Cloud-Init YAML (Etapa 3A-R).
# Comprueba formato #cloud-config, sintaxis YAML, los 3 bloques y scripts embebidos.
set -euo pipefail

# shellcheck source=lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/ca-yaml-test.XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT

frontend_tmpl="${REPO_ROOT}/cloud-init/user-data/frontend.yaml.tmpl"
backend_tmpl="${REPO_ROOT}/cloud-init/user-data/backend.yaml.tmpl"

assert_file "${frontend_tmpl}"
assert_file "${backend_tmpl}"

printf '\n--- 1. Verificando cabecera #cloud-config ---\n'
head -n 1 "${frontend_tmpl}" | grep -q '^#cloud-config' || test_fail "frontend.yaml.tmpl no inicia con #cloud-config"
head -n 1 "${backend_tmpl}" | grep -q '^#cloud-config' || test_fail "backend.yaml.tmpl no inicia con #cloud-config"

printf '\n--- 2. Verificando presencia de los tres bloques obligatorios ---\n'
for tmpl in "${frontend_tmpl}" "${backend_tmpl}"; do
  grep -q '^[[:space:]]*packages:' "${tmpl}" || test_fail "${tmpl} no define bloque packages"
  grep -q '^[[:space:]]*write_files:' "${tmpl}" || test_fail "${tmpl} no define bloque write_files"
  grep -q '^[[:space:]]*runcmd:' "${tmpl}" || test_fail "${tmpl} no define bloque runcmd"
done

printf '\n--- 3. Renderizando plantillas Cloud-Init YAML con variables demo ---\n'
export BACKEND_PRIVATE_IP="10.0.2.10"
export FRONTEND_REPO_URL="https://github.com/ReyMar81/frontend-control-asistencia.git"
export BACKEND_REPO_URL="https://github.com/ReyMar81/backend-control-asistencia.git"
export GIT_BRANCH="main"
export DB_USER="ca_app"
export DB_PASSWORD="DemoPassword2026*"
export DB_NAME="control_asistencia"
export JWT_SECRET="super-secret-jwt-token-with-minimum-32-chars-long"
export CLIENT_URL="http://localhost:5173"
export PORT="3000"

rendered_frontend="${tmp}/frontend.yaml"
rendered_backend="${tmp}/backend.yaml"

"${REPO_ROOT}/scripts/render-user-data.sh" "${frontend_tmpl}" "${rendered_frontend}" >/dev/null
"${REPO_ROOT}/scripts/render-user-data.sh" "${backend_tmpl}" "${rendered_backend}" >/dev/null

assert_file "${rendered_frontend}"
assert_file "${rendered_backend}"

# Verificar que no quedaron placeholders sin sustituir
for file in "${rendered_frontend}" "${rendered_backend}"; do
  if grep -Eq '\$\{[A-Z0-9_]+\}|__[A-Z0-9_]+__' "${file}"; then
    test_fail "quedaron placeholders en ${file}"
  fi
done

printf '\n--- 4. Validando sintaxis YAML y estructura de objetos con Python ---\n'
python - "${rendered_frontend}" "${rendered_backend}" << 'PY'
import sys
import yaml

for path in sys.argv[1:3]:
    with open(path, 'r', encoding='utf-8') as f:
        doc = yaml.safe_load(f)
        assert isinstance(doc, dict), f"{path} no es un diccionario YAML válido"
        for key in ['packages', 'write_files', 'runcmd']:
            assert key in doc, f"Falta clave {key} en {path}"
            assert isinstance(doc[key], list), f"Clave {key} debe ser una lista en {path}"
            assert len(doc[key]) > 0, f"Clave {key} está vacía en {path}"
        print(f"OK YAML: {path} (packages: {len(doc['packages'])}, write_files: {len(doc['write_files'])}, runcmd: {len(doc['runcmd'])})")
PY

printf '\n--- 5. Validando contenido específico del Frontend ---\n'
assert_contains "${rendered_frontend}" "proxy_pass http://10.0.2.10:3000;"
assert_contains "${rendered_frontend}" "location = /healthz"
assert_contains "${rendered_frontend}" "location = /api"
assert_contains "${rendered_frontend}" "VITE_API_URL=/api"
assert_contains "${rendered_frontend}" "deploy-frontend.sh"

printf '\n--- 6. Validando contenido específico del Backend ---\n'
assert_contains "${rendered_backend}" "control-asistencia-backend.service"
assert_contains "${rendered_backend}" "DATABASE_URL=\"postgres://ca_app:DemoPassword2026*@127.0.0.1:5432/control_asistencia\""
assert_contains "${rendered_backend}" "setup-database.sh"
assert_contains "${rendered_backend}" "deploy-backend.sh"
assert_contains "${rendered_backend}" "/api/health"

test_pass "plantillas Cloud-Init YAML de Etapa 3A-R validadas correctamente"
