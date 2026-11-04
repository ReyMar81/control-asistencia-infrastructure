#!/usr/bin/env bash
#
# Utilidades comunes de Cloud-Init.
# No contiene secretos. Todas las rutas son configurables para pruebas locales.
set -euo pipefail

umask 027

CA_SCRIPT_DIR="${CA_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CA_ROLE="${CA_ROLE:-${ROLE:-}}"
CA_AWS_REGION="${CA_AWS_REGION:-${AWS_REGION:-us-east-2}}"
CA_TIMEZONE="${CA_TIMEZONE:-${TIMEZONE:-America/La_Paz}}"
CA_APP_USER="${CA_APP_USER:-controlasistencia}"
CA_APP_GROUP="${CA_APP_GROUP:-controlasistencia}"
CA_APP_HOME="${CA_APP_HOME:-/home/controlasistencia}"
CA_STATE_ROOT="${CA_STATE_ROOT:-/var/lib/control-asistencia}"
CA_LOG_ROOT="${CA_LOG_ROOT:-/var/log/control-asistencia}"
CA_LOG_FILE="${CA_LOG_FILE:-${CA_LOG_ROOT}/bootstrap.log}"
CA_LOG_TO_FILE="${CA_LOG_TO_FILE:-1}"
CA_OPT_ROOT="${CA_OPT_ROOT:-/opt/control-asistencia}"
CA_WWW_ROOT="${CA_WWW_ROOT:-/var/www/control-asistencia}"
CA_ETC_ROOT="${CA_ETC_ROOT:-/etc/control-asistencia}"
CA_SYSTEMD_ROOT="${CA_SYSTEMD_ROOT:-/etc/systemd/system}"
CA_NGINX_ROOT="${CA_NGINX_ROOT:-/etc/nginx}"
CA_PGDATA_ROOT="${CA_PGDATA_ROOT:-/var/lib/pgsql/data}"
CA_OS_RELEASE_FILE="${CA_OS_RELEASE_FILE:-/etc/os-release}"
CA_ARCH="${CA_ARCH:-$(uname -m)}"
CA_TEST_MODE="${CA_TEST_MODE:-0}"
CA_RETRY_COUNT="${CA_RETRY_COUNT:-30}"
CA_RETRY_SLEEP="${CA_RETRY_SLEEP:-2}"
CA_HTTP_TIMEOUT="${CA_HTTP_TIMEOUT:-5}"
CA_CURRENT_STEP="${CA_CURRENT_STEP:-}"

CA_TMP_DIRS=()
CA_TMP_FILES=()

ca_timestamp() {
  date -u '+%Y-%m-%dT%H:%M:%SZ'
}

ca_log() {
  printf '%s [%s] %s\n' "$(ca_timestamp)" "${CA_ROLE:-bootstrap}" "$*"
}

ca_install_dir() {
  local dir="$1"
  local mode="${2:-0755}"
  if [[ "${CA_TEST_MODE}" == "1" ]]; then
    mkdir -p -- "${dir}"
    chmod "${mode}" "${dir}" 2>/dev/null || true
  else
    install -d -m "${mode}" "${dir}"
  fi
}

ca_init_logging() {
  if [[ "${CA_LOG_TO_FILE}" == "1" ]]; then
    ca_install_dir "${CA_LOG_ROOT}" 0750
    touch "${CA_LOG_FILE}"
    chmod 0640 "${CA_LOG_FILE}"
    exec >>"${CA_LOG_FILE}" 2>&1
  fi
  ca_log "Inicio de bootstrap; rol=${CA_ROLE:-desconocido} version=${CA_BUNDLE_VERSION:-desconocida}"
}

ca_register_tmp_dir() {
  CA_TMP_DIRS+=("$1")
}

ca_register_tmp_file() {
  CA_TMP_FILES+=("$1")
}

ca_cleanup_tmp() {
  local path
  trap - ERR
  for path in "${CA_TMP_FILES[@]:-}"; do
    [[ -z "${path}" ]] || rm -f -- "${path}" || true
  done
  for path in "${CA_TMP_DIRS[@]:-}"; do
    [[ -z "${path}" ]] || rm -rf -- "${path}" || true
  done
  return 0
}

ca_die() {
  local message="$*"
  ca_log "ERROR: ${message}"
  if [[ -n "${CA_ROLE}" ]]; then
    ca_fail_run "${message}" || true
  fi
  exit 1
}

ca_on_error() {
  local rc=$?
  local line="$1"
  trap - ERR
  ca_log "ERROR inesperado; codigo=${rc}; linea=${line}; paso=${CA_CURRENT_STEP:-ninguno}"
  if [[ -n "${CA_ROLE}" ]]; then
    ca_fail_run "Fallo inesperado en el paso ${CA_CURRENT_STEP:-desconocido}" || true
  fi
  exit "${rc}"
}

ca_step() {
  CA_CURRENT_STEP="$1"
  ca_log "Paso: ${CA_CURRENT_STEP}"
}

ca_require_root() {
  if [[ "${CA_TEST_MODE}" != "1" && "${EUID}" -ne 0 ]]; then
    ca_die "El bootstrap debe ejecutarse como root."
  fi
}

ca_require_env() {
  local name
  for name in "$@"; do
    if [[ -z "${!name:-}" ]]; then
      ca_die "Variable requerida no definida: ${name}"
    fi
  done
}

ca_require_command() {
  local name
  for name in "$@"; do
    if ! command -v "${name}" >/dev/null 2>&1; then
      ca_die "Comando requerido no disponible: ${name}"
    fi
  done
}

ca_register_error_trap() {
  trap 'ca_on_error ${LINENO}' ERR
}

ca_assert_al2023() {
  [[ -r "${CA_OS_RELEASE_FILE}" ]] || ca_die "No existe ${CA_OS_RELEASE_FILE}."
  local os_id os_version
  os_id="$(unset ID; . "${CA_OS_RELEASE_FILE}"; printf '%s' "${ID:-}")"
  os_version="$(unset VERSION_ID; . "${CA_OS_RELEASE_FILE}"; printf '%s' "${VERSION_ID:-}")"
  [[ "${os_id}" == "amzn" ]] || ca_die "Sistema operativo no soportado: ${os_id:-desconocido}."
  [[ "${os_version}" == "2023" ]] || ca_die "Version de AL2023 no soportada: ${os_version:-desconocida}."
  [[ "${CA_ARCH}" == "x86_64" ]] || ca_die "Arquitectura no soportada: ${CA_ARCH}."
}

ca_state_dir() {
  printf '%s/state/%s' "${CA_STATE_ROOT}" "${CA_ROLE}"
}

ca_mark_step() {
  local step="$1"
  local value="${2:-ok}"
  local dir tmp
  dir="$(ca_state_dir)"
  ca_install_dir "${dir}" 0750
  tmp="${dir}/.${step}.tmp.$$"
  printf '%s\n' "${value}" >"${tmp}"
  chmod 0640 "${tmp}"
  mv -f -- "${tmp}" "${dir}/${step}"
}

ca_step_done() {
  local step="$1"
  local expected="$2"
  local file
  file="$(ca_state_dir)/${step}"
  [[ -f "${file}" ]] && [[ "$(cat "${file}")" == "${expected}" ]]
}

ca_begin_run() {
  local dir tmp
  dir="$(ca_state_dir)"
  ca_install_dir "${dir}" 0750
  rm -f -- "${dir}/failed" "${dir}/complete"
  tmp="${dir}/.in-progress.tmp.$$"
  printf 'started=%s version=%s\n' "$(ca_timestamp)" "${CA_BUNDLE_VERSION:-unknown}" >"${tmp}"
  chmod 0640 "${tmp}"
  mv -f -- "${tmp}" "${dir}/in-progress"
}

ca_complete_run() {
  local dir tmp
  dir="$(ca_state_dir)"
  tmp="${dir}/.complete.tmp.$$"
  printf 'completed=%s version=%s\n' "$(ca_timestamp)" "${CA_BUNDLE_VERSION:-unknown}" >"${tmp}"
  chmod 0640 "${tmp}"
  mv -f -- "${tmp}" "${dir}/complete"
  rm -f -- "${dir}/in-progress"
  ca_log "Bootstrap completado para el rol ${CA_ROLE}."
}

ca_fail_run() {
  local reason="$1"
  local dir tmp
  dir="$(ca_state_dir)"
  ca_install_dir "${dir}" 0750 2>/dev/null || return 0
  tmp="${dir}/.failed.tmp.$$"
  {
    printf 'failed=%s\n' "$(ca_timestamp)"
    printf 'step=%s\n' "${CA_CURRENT_STEP:-desconocido}"
    printf 'reason=%s\n' "${reason}"
  } >"${tmp}" 2>/dev/null || return 0
  chmod 0640 "${tmp}" 2>/dev/null || true
  mv -f -- "${tmp}" "${dir}/failed" 2>/dev/null || true
  rm -f -- "${dir}/in-progress" 2>/dev/null || true
}

ca_ensure_app_user() {
  if [[ "${CA_TEST_MODE}" == "1" ]]; then
    return 0
  fi
  if ! getent group "${CA_APP_GROUP}" >/dev/null 2>&1; then
    groupadd --system "${CA_APP_GROUP}"
  fi
  if ! id -u "${CA_APP_USER}" >/dev/null 2>&1; then
    useradd --system --gid "${CA_APP_GROUP}" --home-dir "${CA_APP_HOME}" \
      --create-home --shell /sbin/nologin "${CA_APP_USER}"
  fi
}

ca_chown() {
  if [[ "${CA_TEST_MODE}" == "1" ]]; then
    return 0
  fi
  chown "$@"
}

ca_run_as_app_env() {
  local dir="$1"
  shift
  if [[ "${CA_TEST_MODE}" == "1" ]]; then
    (cd "${dir}" && env "$@")
  else
    (cd "${dir}" && runuser -u "${CA_APP_USER}" -- env \
      HOME="${CA_APP_HOME}" USER="${CA_APP_USER}" LOGNAME="${CA_APP_USER}" "$@")
  fi
}

ca_render_template() {
  local template="$1"
  local destination="$2"
  shift 2
  [[ -f "${template}" ]] || ca_die "Plantilla no encontrada: ${template}"
  local content
  content="$(cat "${template}")"
  while (( $# > 0 )); do
    local token="$1"
    local value="$2"
    shift 2
    content="${content//${token}/${value}}"
  done
  printf '%s\n' "${content}" >"${destination}"
}

ca_assert_no_placeholders() {
  local file="$1"
  if grep -Eq '__[A-Z0-9_]+__' "${file}"; then
    ca_die "Quedaron placeholders sin sustituir en ${file}."
  fi
}

ca_install_file() {
  local source="$1"
  local destination="$2"
  local mode="$3"
  [[ -f "${source}" ]] || ca_die "Archivo no encontrado: ${source}"
  ca_install_dir "$(dirname "${destination}")" 0755
  install -m "${mode}" "${source}" "${destination}"
}

ca_configure_timezone() {
  [[ "${CA_TIMEZONE}" == "America/La_Paz" ]] || ca_die "Zona horaria no permitida: ${CA_TIMEZONE}."
  ca_require_command timedatectl
  timedatectl set-timezone "${CA_TIMEZONE}"
  local current
  current="$(timedatectl show --property=Timezone --value 2>/dev/null || true)"
  if [[ -n "${current}" && "${current}" != "${CA_TIMEZONE}" ]]; then
    ca_die "No se pudo confirmar la zona horaria ${CA_TIMEZONE}."
  fi
}

ca_sha256_file() {
  local file="$1"
  [[ -f "${file}" && ! -L "${file}" ]] || ca_die "Archivo no valido para checksum: ${file}"
  sha256sum "${file}" | awk '{print tolower($1)}'
}

ca_validate_sha256_format() {
  [[ "$1" =~ ^[a-fA-F0-9]{64}$ ]]
}

ca_verify_sha256() {
  local file="$1"
  local expected="${2,,}"
  ca_validate_sha256_format "${expected}" || ca_die "Checksum esperado invalido."
  local actual
  actual="$(ca_sha256_file "${file}")"
  if [[ "${actual}" != "${expected}" ]]; then
    ca_die "Checksum SHA-256 no coincide para $(basename "${file}")."
  fi
  ca_log "Checksum verificado: $(basename "${file}") ${actual}"
}

ca_download_s3() {
  local bucket="$1"
  local key="$2"
  local destination="$3"
  ca_require_command aws
  if ! aws --version 2>&1 | grep -q 'aws-cli/2\.'; then
    ca_die "Se requiere AWS CLI v2."
  fi
  ca_install_dir "$(dirname "${destination}")" 0700
  aws s3 cp --only-show-errors --region "${CA_AWS_REGION}" \
    "s3://${bucket}/${key}" "${destination}"
  [[ -f "${destination}" && ! -L "${destination}" ]] || ca_die "No se descargo el objeto S3 esperado."
}

ca_safe_extract_tar() {
  local archive="$1"
  local destination="$2"
  [[ -f "${archive}" && ! -L "${archive}" ]] || ca_die "Archivo tar invalido."
  [[ -n "${destination}" && "${destination}" != "/" ]] || ca_die "Destino de extraccion invalido."

  local entry
  while IFS= read -r entry; do
    [[ -z "${entry}" ]] && continue
    if [[ "${entry}" == /* || "${entry}" == \\* ]]; then
      ca_die "El tar contiene una ruta absoluta."
    fi
    if [[ "/${entry}/" == *"/../"* ]]; then
      ca_die "El tar contiene una ruta con .."
    fi
  done < <(tar -tzf "${archive}")

  local listing
  if ! listing="$(tar -tvzf "${archive}")"; then
    ca_die "No se pudo listar el tar."
  fi
  if printf '%s\n' "${listing}" | awk '$1 ~ /^[lh]/ {found=1} END {exit (found ? 0 : 1)}'; then
    ca_die "El tar contiene enlaces simbolicos o duros; no se permite."
  fi

  ca_install_dir "${destination}" 0700
  tar -xzf "${archive}" -C "${destination}" --no-same-owner --no-same-permissions
  if find "${destination}" -type l -print -quit | grep -q .; then
    ca_die "La extraccion produjo enlaces simbolicos."
  fi
}

ca_replace_managed_block() {
  local file="$1"
  local begin="$2"
  local end="$3"
  local content="$4"
  local tmp="${file}.tmp.$$"
  touch "${file}"
  if grep -qF "${begin}" "${file}"; then
    awk -v begin="${begin}" -v end="${end}" '
      $0 == begin { print; skipping = 1; next }
      $0 == end { skipping = 0; next }
      !skipping { print }
    ' "${file}" >"${tmp}"
  else
    cp "${file}" "${tmp}"
  fi
  printf '%s\n' "${begin}" >>"${tmp}"
  printf '%s\n' "${content}" >>"${tmp}"
  printf '%s\n' "${end}" >>"${tmp}"
  mv -f -- "${tmp}" "${file}"
}

ca_env_quote() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '"%s"' "${value}"
}

ca_wait_http() {
  local url="$1"
  local attempt
  for (( attempt = 1; attempt <= CA_RETRY_COUNT; attempt++ )); do
    if curl -fsS --max-time "${CA_HTTP_TIMEOUT}" -o /dev/null "${url}"; then
      ca_log "Salud confirmada: ${url}"
      return 0
    fi
    sleep "${CA_RETRY_SLEEP}"
  done
  return 1
}

ca_wait_postgres() {
  local attempt
  ca_require_command pg_isready
  for (( attempt = 1; attempt <= CA_RETRY_COUNT; attempt++ )); do
    if pg_isready -h 127.0.0.1 -p 5432 >/dev/null 2>&1; then
      ca_log "PostgreSQL acepta conexiones locales."
      return 0
    fi
    sleep "${CA_RETRY_SLEEP}"
  done
  return 1
}

ca_atomic_link() {
  local target="$1"
  local link="$2"
  ca_install_dir "$(dirname "${link}")" 0755
  if [[ -e "${link}" && ! -L "${link}" ]]; then
    rm -rf -- "${link}"
  fi
  ln -sfn "${target}" "${link}"
}
