#!/usr/bin/env bash
# One command for the whole Solace Cloud path: broker service (Terraform),
# broker configuration (SEMP), Cloud-Managed Micro-Integration (API).
# It only calls the scripts documented in cloud-setup/README.md, in order.
#
# Usage: ./setup-cloud.sh <preflight|up|down|status> [--yes]
#
#   preflight  check tools and input files, change nothing
#   up         create everything: terraform init+apply, show-service-connection,
#              get-service-endpoints, configure-cloud-broker, then the
#              Micro-Integration create, create-flow and deploy. Safe to
#              re-run: finished steps are skipped or repeated harmlessly.
#   down       remove everything: undeploy and delete the Micro-Integration,
#              then terraform destroy
#   status     show the Micro-Integration state
#
# --yes skips the terraform confirmation prompts (apply, destroy).
#
# One manual step remains, creating the API token (see README.md).
# Inputs: solace-cloud-api/.env, terraform/terraform.tfvars and
# ../zerobus-integration/.env (Databricks values).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
API_DIR="${SCRIPT_DIR}/solace-cloud-api"
TF_DIR="${SCRIPT_DIR}/terraform"
REPO_ROOT="${SCRIPT_DIR}/.."
STATE_FILE="${REPO_ROOT}/output/micro-integration.json"

CMD="${1:-}"
YES=""
[[ "${2:-}" == "--yes" ]] && YES="-auto-approve"
case "${CMD}" in preflight|up|down|status) ;; *)
  echo "Usage: $0 <preflight|up|down|status> [--yes]" >&2; exit 1;; esac

step() { echo; echo "=== $* ==="; }

preflight() {
  local missing=0
  for tool in curl jq openssl terraform; do
    command -v "${tool}" >/dev/null 2>&1 || { echo "Missing tool: ${tool}" >&2; missing=1; }
  done
  [[ -f "${API_DIR}/.env" ]] || { echo "Missing ${API_DIR}/.env (copy .env.example, add the API token)." >&2; missing=1; }
  [[ -f "${TF_DIR}/terraform.tfvars" ]] || { echo "Missing ${TF_DIR}/terraform.tfvars (copy terraform.tfvars.example, set datacenter_id)." >&2; missing=1; }
  if [[ -f "${REPO_ROOT}/zerobus-integration/.env" ]]; then
    # shellcheck disable=SC1090,SC1091
    ( set -a; source "${REPO_ROOT}/zerobus-integration/.env"; set +a
      for v in DATABRICKS_URL DATABRICKS_SERVER_ENDPOINT DATABRICKS_CLIENT_ID DATABRICKS_CLIENT_SECRET DATABRICKS_CATALOG DATABRICKS_SCHEMA DATABRICKS_TABLE; do
        [[ -n "${!v:-}" && "${!v}" != CHANGEME* ]] || { echo "${v} is not set in zerobus-integration/.env" >&2; exit 1; }
      done ) || missing=1
  else
    echo "Missing zerobus-integration/.env (Databricks values, runbook 1.5)." >&2; missing=1
  fi
  [[ "${missing}" -eq 0 ]] || { echo "Preflight failed." >&2; exit 1; }
  echo "Preflight OK."
}

case "${CMD}" in
preflight)
  preflight ;;
up)
  preflight
  step "1/9 Terraform init"; "${TF_DIR}/run-terraform.sh" init
  step "2/9 Terraform apply (creates the broker service, about 5 minutes)"; "${TF_DIR}/run-terraform.sh" apply ${YES}
  step "3/9 Connection details"; "${API_DIR}/show-service-connection.sh"
  step "4/9 Service endpoints"; "${API_DIR}/get-service-endpoints.sh"
  step "5/9 Configure the broker"; "${API_DIR}/configure-cloud-broker.sh"
  step "6/9 Create the Micro-Integration"; "${API_DIR}/micro-integration.sh" create
  step "7/9 Create the flow"; "${API_DIR}/micro-integration.sh" create-flow
  step "8/9 Deploy (waits until running)"; "${API_DIR}/micro-integration.sh" deploy
  step "9/9 Status"; "${API_DIR}/micro-integration.sh" status
  echo
  echo "Done. Test: cd demo-apps && source .venv/bin/activate && python publisher.py --target cloud --count 5"
  ;;
down)
  if [[ -f "${STATE_FILE}" ]]; then
    step "Undeploy the Micro-Integration"; "${API_DIR}/micro-integration.sh" undeploy || true
    step "Delete the Micro-Integration (retries until it has stopped)"
    deleted=0
    for i in $(seq 1 18); do
      if "${API_DIR}/micro-integration.sh" delete; then deleted=1; break; fi
      echo "Not deletable yet, retrying in 10 s (${i}/18)..."; sleep 10
    done
    [[ "${deleted}" -eq 1 ]] || { echo "Could not delete the Micro-Integration; check ./solace-cloud-api/micro-integration.sh status." >&2; exit 1; }
  else
    echo "No Micro-Integration recorded (${STATE_FILE}), skipping."
  fi
  step "Terraform destroy"; "${TF_DIR}/run-terraform.sh" destroy ${YES}
  ;;
status)
  "${API_DIR}/micro-integration.sh" status ;;
esac
