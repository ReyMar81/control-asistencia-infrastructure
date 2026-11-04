#!/usr/bin/env bash
#
# Envía la actualización frontend por SSM y espera el resultado remoto.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  printf 'Uso: deploy-frontend.sh <INSTANCE_ID> [AWS_REGION]\n' >&2
  exit 1
fi

instance_id="$1"
region="${2:-${AWS_REGION:-us-east-2}}"

printf 'Enviando comando frontend a %s en %s...\n' "${instance_id}" "${region}"
command_id="$(
  aws ssm send-command \
    --region "${region}" \
    --instance-ids "${instance_id}" \
    --document-name "AWS-RunShellScript" \
    --comment "Despliegue continuo frontend vía git push" \
    --parameters 'commands=["/usr/local/bin/deploy-frontend.sh"]' \
    --timeout-seconds 900 \
    --query 'Command.CommandId' \
    --output text
)"

printf 'Comando SSM %s enviado; esperando resultado...\n' "${command_id}"
while :; do
  if ! status="$(
      aws ssm get-command-invocation \
        --region "${region}" \
        --command-id "${command_id}" \
        --instance-id "${instance_id}" \
        --query 'Status' \
        --output text
    )"; then
    sleep 5
    continue
  fi
  case "${status}" in
    Pending|InProgress|Delayed)
      sleep 5
      ;;
    Success)
      aws ssm get-command-invocation \
        --region "${region}" \
        --command-id "${command_id}" \
        --instance-id "${instance_id}" \
        --query 'StandardOutputContent' \
        --output text
      exit 0
      ;;
    *)
      aws ssm get-command-invocation \
        --region "${region}" \
        --command-id "${command_id}" \
        --instance-id "${instance_id}" \
        --query '{Status:Status,Details:StatusDetails,Output:StandardOutputContent,Error:StandardErrorContent}' \
        --output json >&2
      exit 1
      ;;
  esac
done
