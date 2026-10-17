#!/usr/bin/env bash
# Fetches the Broker Manager admin (manager-role) username/password for
# one or more Terraform-managed Solace Cloud services and writes them to
# ../../output/broker-admin-credentials.json.
#
# Source: Terraform state (`terraform output -json`), NOT a curl to the
# Mission Control REST API -- the public GET for a service does not
# return management-credential fields. See ../../docs/notes-and-gotchas.md
# ("Mission Control API does not return broker-management credentials").
#
# Requires: the `terraform` CLI, jq, and up-to-date state in
# ../terraform/ (i.e. the service(s) already exist there).
#
# Usage:
#   ./get-broker-manager-credentials.sh <terraform-output-name> [<terraform-output-name> ...]
#   ./get-broker-manager-credentials.sh service

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/../terraform"
OUTPUT_DIR="${SCRIPT_DIR}/../../output"
mkdir -p "${OUTPUT_DIR}"

command -v terraform >/dev/null 2>&1 || { echo "terraform CLI is required for this script." >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required for this script." >&2; exit 1; }

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <terraform-output-name> [<terraform-output-name> ...]" >&2
  exit 1
fi

extract() {
  local output_name="$1"
  terraform -chdir="${TERRAFORM_DIR}" output -json "${output_name}" \
    | jq '{adminUsername: .message_vpn.manager_management_credential.username,
           adminPassword: .message_vpn.manager_management_credential.password}'
}

JQ_ARGS=()
JQ_FILTER="{"
first=true
for name in "$@"; do
  JQ_ARGS+=(--argjson "${name}" "$(extract "${name}")")
  if [[ "${first}" == true ]]; then first=false; else JQ_FILTER+=","; fi
  JQ_FILTER+="\"${name}\": \$${name}"
done
JQ_FILTER+="}"

jq -n "${JQ_ARGS[@]}" "${JQ_FILTER}" > "${OUTPUT_DIR}/broker-admin-credentials.json"

echo "Written: ${OUTPUT_DIR}/broker-admin-credentials.json"
echo
echo "If adminUsername/adminPassword are 'null': run 'terraform apply' (or"
echo "'terraform refresh') in ../terraform/ so state is current, and check"
echo "with 'terraform output -json <name> | jq .' whether the field"
echo "message_vpn.manager_management_credential is really there."
