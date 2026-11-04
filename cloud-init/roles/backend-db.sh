#!/usr/bin/env bash
#
# Rol backend-db: Node.js, PostgreSQL, esquema, systemd y salud.
set -euo pipefail

ca_backend_release() {
  local sha="${CA_BACKEND_ARTIFACT_SHA256,,}"
  local release_root="${CA_OPT_ROOT}/backend/releases"
  local release_name="${CA_BUNDLE_VERSION}-${sha:0:12}"
  local release_dir="${release_root}/${release_name}"
  local marker="backend-release-${release_name}"

  CA_BACKEND_RELEASE_DIR="${release_dir}"
  if ca_step_done "${marker}" "${release_name}" \
    && [[ -f "${release_dir}/package.json" ]] \
    && [[ -f "${release_dir}/src/server.js" ]] \
    && [[ -f "${release_dir}/schema.sql" ]]; then
    ca_log "Release de backend ya instalada: ${release_name}."
    return 0
  fi

  ca_step "Descargando e instalando backend ${CA_BUNDLE_VERSION}"
  local work archive app
  work="$(mktemp -d "${TMPDIR:-/tmp}/ca-backend.XXXXXX")"
  ca_register_tmp_dir "${work}"
  archive="${work}/backend.tar.gz"
  app="${work}/app"

  ca_download_s3 "${CA_ARTIFACT_BUCKET}" "${CA_BACKEND_ARTIFACT_KEY}" "${archive}"
  ca_verify_sha256 "${archive}" "${sha}"
  ca_safe_extract_tar "${archive}" "${app}"

  [[ -f "${app}/package.json" ]] || ca_die "El artefacto backend no contiene package.json."
  [[ -f "${app}/package-lock.json" ]] || ca_die "El artefacto backend no contiene package-lock.json."
  [[ -f "${app}/schema.sql" ]] || ca_die "El artefacto backend no contiene schema.sql."
  [[ -f "${app}/src/server.js" ]] || ca_die "El artefacto backend no contiene src/server.js."
  ca_chown -R "${CA_APP_USER}:${CA_APP_GROUP}" "${app}"

  ca_run_as_app_env "${app}" npm ci --omit=dev --no-audit --no-fund
  node --check "${app}/src/server.js"

  ca_install_dir "${release_root}" 0755
  rm -rf -- "${release_dir}"
  mv -- "${app}" "${release_dir}"
  ca_chown -R "${CA_APP_USER}:${CA_APP_GROUP}" "${release_dir}"
  ca_mark_step "${marker}" "${release_name}"
  ca_log "Release de backend instalada: ${release_name}."
}

ca_install_backend_unit() {
  local unit_tmp unit_path node_bin
  node_bin="$(command -v node)"
  [[ -n "${node_bin}" ]] || ca_die "No se encontro el binario de Node.js."
  node_bin="$(readlink -f "${node_bin}" 2>/dev/null || printf '%s' "${node_bin}")"
  [[ -x "${node_bin}" ]] || ca_die "El binario de Node.js no es ejecutable."

  ca_install_dir "${CA_SYSTEMD_ROOT}" 0755
  unit_path="${CA_SYSTEMD_ROOT}/control-asistencia-backend.service"
  unit_tmp="$(mktemp "${TMPDIR:-/tmp}/ca-backend-unit.XXXXXX")"
  ca_register_tmp_file "${unit_tmp}"
  ca_render_template \
    "${CA_SCRIPT_DIR}/files/control-asistencia-backend.service.tmpl" \
    "${unit_tmp}" \
    "__NODE_BIN__" "${node_bin}" \
    "__BACKEND_ROOT__" "${CA_OPT_ROOT}/backend/current" \
    "__ENV_FILE__" "${CA_ETC_ROOT}/backend.env" \
    "__TIMEZONE__" "${CA_TIMEZONE}" \
    "__APP_USER__" "${CA_APP_USER}" \
    "__APP_GROUP__" "${CA_APP_GROUP}"
  ca_assert_no_placeholders "${unit_tmp}"
  install -m 0644 "${unit_tmp}" "${unit_path}"
  rm -f -- "${unit_tmp}"

  systemctl daemon-reload
  systemctl enable control-asistencia-backend
  systemctl restart control-asistencia-backend
  ca_log "Servicio control-asistencia-backend reiniciado."
}

ca_backend_main() {
  ca_backend_release
  ca_load_secret
  ca_configure_postgres
  ca_setup_database "${CA_BACKEND_RELEASE_DIR}/schema.sql"
  ca_write_backend_env
  ca_atomic_link "${CA_BACKEND_RELEASE_DIR}" "${CA_OPT_ROOT}/backend/current"
  ca_install_backend_unit
  ca_wait_http "http://127.0.0.1:3000/api/health" || ca_die "El backend no responde en /api/health."
  ca_log "Backend y PostgreSQL configurados."
}
