#!/usr/bin/env bash
#
# Instalacion de paquetes AL2023 y verificacion de versiones.
set -euo pipefail

ca_package_marker() {
  printf '%s/package-%s' "$(ca_state_dir)" "$1"
}

ca_install_base_packages() {
  local marker
  marker="$(ca_package_marker base)"
  if ca_step_done "package-base" "installed" && [[ "${CA_FORCE_PACKAGE_REFRESH:-0}" != "1" ]]; then
    ca_log "Paquetes base ya instalados; se omite dnf."
  else
    ca_step "Instalando paquetes base"
    dnf install -y tar gzip shadow-utils util-linux curl-minimal amazon-ssm-agent
    if command -v rpm >/dev/null 2>&1 && ! rpm -q amazon-ssm-agent >/dev/null 2>&1; then
      ca_die "No se pudo verificar amazon-ssm-agent."
    fi
    systemctl enable --now amazon-ssm-agent
    ca_mark_step "package-base" "installed"
    ca_log "Paquetes base instalados."
  fi
  ca_require_command aws
  aws --version 2>&1 | grep -q 'aws-cli/2\.' || ca_die "Se requiere AWS CLI v2."
}

ca_install_frontend_packages() {
  if ca_step_done "package-frontend" "installed" && [[ "${CA_FORCE_PACKAGE_REFRESH:-0}" != "1" ]]; then
    ca_log "Paquetes frontend ya instalados; se omite dnf."
  else
    ca_step "Instalando Node.js 24 y Nginx"
    dnf install -y nodejs24 nginx
    ca_mark_step "package-frontend" "installed"
  fi
  ca_verify_node
  ca_verify_nginx
}

ca_install_backend_packages() {
  if ca_step_done "package-backend" "installed" && [[ "${CA_FORCE_PACKAGE_REFRESH:-0}" != "1" ]]; then
    ca_log "Paquetes backend ya instalados; se omite dnf."
  else
    ca_step "Instalando Node.js 24 y PostgreSQL 17"
    dnf install -y nodejs24 postgresql17 postgresql17-server postgresql17-contrib
    ca_mark_step "package-backend" "installed"
  fi
  ca_verify_node
  ca_verify_postgres
}

ca_verify_node() {
  ca_require_command node npm
  local version
  version="$(node --version)"
  [[ "${version}" =~ ^v24\. ]] || ca_die "Node.js 24 es requerido; version actual: ${version}."
  ca_log "Node.js ${version}; npm $(npm --version)."
}

ca_verify_nginx() {
  ca_require_command nginx
  nginx -v 2>&1 | grep -q 'nginx version' || ca_die "Nginx no responde a -v."
}

ca_verify_postgres() {
  ca_require_command psql postgresql-setup pg_isready
  psql --version | grep -q '17\.' || ca_die "PostgreSQL 17 es requerido."
}
