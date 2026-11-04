#!/usr/bin/env bash
#
# Punto de entrada del bundle de Cloud-Init.
set -euo pipefail

CA_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CA_SCRIPT_DIR

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role)
      [[ $# -ge 2 ]] || { printf 'Falta el valor de --role\n' >&2; exit 2; }
      CA_ROLE="$2"
      shift 2
      ;;
    --help|-h)
      printf 'Uso: %s --role frontend|backend-db\n' "$0"
      exit 0
      ;;
    *)
      printf 'Argumento no reconocido: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

CA_ROLE="${CA_ROLE:-${ROLE:-}}"
export CA_ROLE

# shellcheck source=common/lib.sh
source "${CA_SCRIPT_DIR}/common/lib.sh"
# shellcheck source=common/validate.sh
source "${CA_SCRIPT_DIR}/common/validate.sh"
# shellcheck source=common/packages.sh
source "${CA_SCRIPT_DIR}/common/packages.sh"
# shellcheck source=common/secrets.sh
source "${CA_SCRIPT_DIR}/common/secrets.sh"
# shellcheck source=common/postgres.sh
source "${CA_SCRIPT_DIR}/common/postgres.sh"

ca_register_error_trap
trap ca_cleanup_tmp EXIT

ca_require_root
ca_assert_al2023
ca_validate_role
ca_init_logging
ca_begin_run

if [[ "${CA_ROLE}" == "frontend" ]]; then
  # shellcheck source=roles/frontend.sh
  source "${CA_SCRIPT_DIR}/roles/frontend.sh"
  ca_validate_frontend_env
  ca_configure_timezone
  ca_ensure_app_user
  ca_install_base_packages
  ca_install_frontend_packages
  ca_frontend_main
else
  # shellcheck source=roles/backend-db.sh
  source "${CA_SCRIPT_DIR}/roles/backend-db.sh"
  ca_validate_backend_env
  ca_configure_timezone
  ca_ensure_app_user
  ca_install_base_packages
  ca_install_backend_packages
  ca_backend_main
fi

ca_complete_run
