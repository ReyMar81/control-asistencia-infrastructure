#!/usr/bin/env bash
#
# Rol frontend: build de la SPA, Nginx y proxy /api/.
set -euo pipefail

ca_frontend_release() {
  local sha="${CA_FRONTEND_ARTIFACT_SHA256,,}"
  local release_root="${CA_OPT_ROOT}/frontend/releases"
  local release_name="${CA_BUNDLE_VERSION}-${sha:0:12}"
  local release_dir="${release_root}/${release_name}"
  local marker="frontend-release-${release_name}"

  CA_FRONTEND_RELEASE_DIR="${release_dir}"
  if ca_step_done "${marker}" "${release_name}" && [[ -f "${release_dir}/index.html" ]]; then
    ca_log "Release de frontend ya construida: ${release_name}."
    return 0
  fi

  ca_step "Descargando y construyendo frontend ${CA_BUNDLE_VERSION}"
  local work archive app
  work="$(mktemp -d "${TMPDIR:-/tmp}/ca-frontend.XXXXXX")"
  ca_register_tmp_dir "${work}"
  archive="${work}/frontend.tar.gz"
  app="${work}/app"

  ca_download_s3 "${CA_ARTIFACT_BUCKET}" "${CA_FRONTEND_ARTIFACT_KEY}" "${archive}"
  ca_verify_sha256 "${archive}" "${sha}"
  ca_safe_extract_tar "${archive}" "${app}"

  [[ -f "${app}/package.json" ]] || ca_die "El artefacto frontend no contiene package.json."
  [[ -f "${app}/package-lock.json" ]] || ca_die "El artefacto frontend no contiene package-lock.json."
  ca_chown -R "${CA_APP_USER}:${CA_APP_GROUP}" "${app}"

  ca_run_as_app_env "${app}" npm ci --no-audit --no-fund
  ca_run_as_app_env "${app}" VITE_API_URL=/api npm run build
  [[ -f "${app}/dist/index.html" ]] || ca_die "El build del frontend no genero dist/index.html."

  ca_install_dir "${release_root}" 0755
  rm -rf -- "${release_dir}"
  ca_install_dir "${release_dir}" 0755
  cp -a "${app}/dist/." "${release_dir}/"
  chmod -R u=rwX,go=rX "${release_dir}"
  ca_mark_step "${marker}" "${release_name}"
  ca_log "Release de frontend publicada: ${release_name}."
}

ca_frontend_nginx() {
  local site_tmp hash marker site_path
  site_path="${CA_NGINX_ROOT}/conf.d/control-asistencia.conf"
  site_tmp="$(mktemp "${TMPDIR:-/tmp}/ca-nginx-site.XXXXXX")"
  ca_register_tmp_file "${site_tmp}"

  ca_render_template \
    "${CA_SCRIPT_DIR}/files/nginx-control-asistencia.conf.tmpl" \
    "${site_tmp}" \
    "__BACKEND_PRIVATE_IP__" "${CA_BACKEND_PRIVATE_IP}" \
    "__FRONTEND_ROOT__" "${CA_WWW_ROOT}/current"
  ca_assert_no_placeholders "${site_tmp}"
  hash="$(ca_sha256_file "${site_tmp}")"
  marker="nginx-${hash:0:16}"

  if ! ca_step_done "${marker}" "configured" || [[ ! -f "${site_path}" ]]; then
    ca_step "Configurando Nginx"
    ca_install_file "${CA_SCRIPT_DIR}/files/nginx.conf" "${CA_NGINX_ROOT}/nginx.conf" 0644
    ca_install_dir "${CA_NGINX_ROOT}/conf.d" 0755
    install -m 0644 "${site_tmp}" "${site_path}"
    rm -f -- "${CA_NGINX_ROOT}/conf.d/default.conf"
    nginx -t
    ca_mark_step "${marker}" "configured"
  else
    ca_log "Configuracion de Nginx ya aplicada."
  fi

  rm -f -- "${site_tmp}"
  systemctl enable --now nginx
  systemctl reload nginx || systemctl restart nginx
  ca_wait_http "http://127.0.0.1/healthz" || ca_die "Nginx no responde en /healthz."
}

ca_frontend_main() {
  ca_frontend_release
  ca_atomic_link "${CA_FRONTEND_RELEASE_DIR}" "${CA_WWW_ROOT}/current"
  ca_frontend_nginx
  ca_log "Frontend configurado."
}
