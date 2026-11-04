#!/usr/bin/env bash
#
# Comprobación estática de patrones de secretos en el repositorio.
# No accede a AWS ni modifica archivos.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
errors=0

search() {
  local pattern="$1"
  local description="$2"
  local matches

  matches="$(grep -RInE --exclude-dir=.git --exclude-dir=.terraform --exclude-dir=node_modules --exclude-dir=.pulumi -- "${pattern}" "${repo_root}" || true)"

  if [[ -n "${matches}" ]]; then
    printf 'Posible secreto (%s):\n%s\n' "${description}" "${matches}" >&2
    errors=$((errors + 1))
  fi
}

search 'AKIA[0-9A-Z]{16}' 'AWS access key ID'
search 'aws_secret_access_key[[:space:]]*=' 'AWS secret access key'
search 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY' 'clave privada'
search 'xox[baprs]-[0-9A-Za-z-]+' 'token de Slack'
search 'gh[pousr]_[0-9A-Za-z]{20,}' 'token de GitHub'

if ! grep -q '^\*\.tfstate' "${repo_root}/.gitignore"; then
  printf '.gitignore no excluye *.tfstate\n' >&2
  errors=$((errors + 1))
fi

if ! grep -q '^\.env$' "${repo_root}/.gitignore"; then
  printf '.gitignore no excluye .env\n' >&2
  errors=$((errors + 1))
fi

if (( errors > 0 )); then
  printf 'Comprobación de secretos falló con %d hallazgo(s).\n' "${errors}" >&2
  exit 1
fi

printf 'Comprobación de secretos: OK\n'
