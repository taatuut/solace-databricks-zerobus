#!/usr/bin/env bash
# Runs terraform for this folder with the Solace Cloud API token and base
# URL taken from ../solace-cloud-api/.env (single source of truth), so the
# token is never copied into terraform.tfvars.
#
# Usage: ./run-terraform.sh <init|plan|apply|destroy|output|...> [args]
# Examples:
#   ./run-terraform.sh init
#   ./run-terraform.sh plan
#   ./run-terraform.sh apply
#   ./run-terraform.sh output -json service

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../solace-cloud-api/.env"

command -v terraform >/dev/null 2>&1 || { echo "terraform CLI is required (brew install terraform)." >&2; exit 1; }
[[ -f "${ENV_FILE}" ]] || { echo "Missing ${ENV_FILE} (copy .env.example and fill it in)." >&2; exit 1; }
[[ -f "${SCRIPT_DIR}/terraform.tfvars" ]] || { echo "Missing terraform.tfvars (copy terraform.tfvars.example)." >&2; exit 1; }
[[ $# -ge 1 ]] || { echo "Usage: $0 <terraform command> [args]" >&2; exit 1; }

# shellcheck disable=SC1090
source "${ENV_FILE}"
: "${SOLACE_CLOUD_API_TOKEN:?Set SOLACE_CLOUD_API_TOKEN in ${ENV_FILE}}"
: "${SOLACE_CLOUD_API_BASE:?Set SOLACE_CLOUD_API_BASE in ${ENV_FILE}}"

export TF_VAR_solace_cloud_api_token="${SOLACE_CLOUD_API_TOKEN}"
# The provider wants the base URL without the /api/v2 suffix, with a
# trailing slash (https://api.solace.cloud/).
export TF_VAR_solace_cloud_api_base_url="${SOLACE_CLOUD_API_BASE%api/v2}"

exec terraform -chdir="${SCRIPT_DIR}" "$@"
