#!/usr/bin/env bash
# Manages the Cloud-Managed Databricks Zerobus Micro-Integration through the
# (Beta) Solace Cloud Micro-Integration API.
#
# Usage: ./micro-integration.sh <create|create-flow|deploy|status|inspect|undeploy|delete>
#
#   create       POST the Micro-Integration with its connection settings
#                (Databricks + Solace broker; state: notdeployed), remember its id
#   create-flow  POST the Flow (queue -> table, DMQ) that
#                belongs to it; flow settings are NOT accepted on the
#                Micro-Integration itself
#   deploy       PATCH state=deploying and wait until it is running (or errors)
#   status       show state of the Micro-Integration and its flows
#   inspect      dump the full API records (redacted) incl. deployment details
#   undeploy     PATCH state=undeploying
#   delete       DELETE the flow(s) and the Micro-Integration (undeploy first)
#
# Inputs (nothing secret is printed):
#   ../../output/service.json, service-endpoints.json   (service id, environment)
#   ../../output/cloud-broker.env                       (broker user/password, from configure-cloud-broker.sh)
#   ../../zerobus-integration/.env                      (Databricks values, shared with the local path)
#   .env                                                (Solace Cloud API token and base URL)
# The API builds the type id as <microIntegrationType>-<direction>, so the
# request says type "databricks-zerobus" + direction "target" (the listing
# shows the combined id "databricks-zerobus-target").
# Keys of the request body follow the templates from
# discover-micro-integration.sh (see ../../docs/cloud-managed-micro-integration.md).
# Needs a token with micro_integrations:*:*.
# DRY_RUN=1 ./micro-integration.sh create   prints the redacted body, sends nothing.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/../../output"
STATE_FILE="${OUTPUT_DIR}/micro-integration.json"
FLOW_FILE="${OUTPUT_DIR}/micro-integration-flow.json"
MI_NAME="${MI_NAME:-ez-zerobus-demo-mi}"

CMD="${1:-}"
case "${CMD}" in create|create-flow|deploy|status|inspect|undeploy|delete) ;; *)
  echo "Usage: $0 <create|create-flow|deploy|status|inspect|undeploy|delete>" >&2; exit 1;; esac

command -v jq >/dev/null 2>&1 || { echo "jq is required (brew install jq)." >&2; exit 1; }
# shellcheck disable=SC1090
source "${SCRIPT_DIR}/.env"
: "${SOLACE_CLOUD_API_TOKEN:?Set SOLACE_CLOUD_API_TOKEN in ${SCRIPT_DIR}/.env}"
: "${SOLACE_CLOUD_API_BASE:=https://api.solace.cloud/api/v2}"
API="${SOLACE_CLOUD_API_BASE}/integration/microIntegrations"
FLOW_API="${SOLACE_CLOUD_API_BASE}/integration/microIntegrationFlows"
MI_FLOW_NAME="${MI_FLOW_NAME:-ez-zerobus-demo-flow}"
mkdir -p "${OUTPUT_DIR}"

redact() {
  jq 'walk(if type == "object"
           then with_entries(if (.key | test("password|secret|token"; "i")) then .value = "<redacted>" else . end)
           else . end)'
}

call() {
  # call METHOD URL OUTFILE [curl args...]; fails on non-2xx
  local method="$1" url="$2" out="$3"; shift 3
  local code
  code=$(curl -sS -X "${method}" -o "${out}" -w '%{http_code}' \
    -H "Authorization: Bearer ${SOLACE_CLOUD_API_TOKEN}" "$@" "${url}")
  if [[ "${code}" != 2* ]]; then
    echo "${method} ${url} -> HTTP ${code}" >&2
    if jq -e . "${out}" >/dev/null 2>&1; then redact < "${out}" >&2; else cat "${out}" >&2; fi
    echo >&2
    return 1
  fi
}

mi_id() {
  [[ -f "${STATE_FILE}" ]] || { echo "No ${STATE_FILE}: run '$0 create' first." >&2; exit 1; }
  jq -r '.data.id' "${STATE_FILE}"
}

show_state() {
  local tmp; tmp="$(mktemp)"
  call GET "${API}/$(mi_id)?includeLatestDeployment=true" "${tmp}"
  jq '.data | {id, name, state, brokerId, environmentId, deployment: .microIntegrationDeploymentDetail}' "${tmp}" | redact
  jq -r '.data.state' "${tmp}" > "${tmp}.state"
  STATE="$(cat "${tmp}.state")"
  if call GET "${FLOW_API}?microIntegrationId=$(mi_id)" "${tmp}" 2>/dev/null; then
    echo "flows:"
    jq -c '.data[]? | {id, name, state}' "${tmp}"
  fi
  rm -f "${tmp}" "${tmp}.state"
}

case "${CMD}" in
create)
  for f in service.json service-endpoints.json cloud-broker.env; do
    [[ -f "${OUTPUT_DIR}/${f}" ]] || { echo "Missing ${OUTPUT_DIR}/${f} (see cloud-setup/README.md, order of operations)." >&2; exit 1; }
  done
  [[ -f "${SCRIPT_DIR}/../../zerobus-integration/.env" ]] || { echo "Missing zerobus-integration/.env (Databricks values)." >&2; exit 1; }
  # shellcheck disable=SC1090
  source "${OUTPUT_DIR}/cloud-broker.env"
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/../../zerobus-integration/.env"
  for v in DATABRICKS_URL DATABRICKS_SERVER_ENDPOINT DATABRICKS_CLIENT_ID DATABRICKS_CLIENT_SECRET DATABRICKS_CATALOG DATABRICKS_SCHEMA DATABRICKS_TABLE; do
    [[ -n "${!v:-}" && "${!v}" != CHANGEME* ]] || { echo "${v} is not set in zerobus-integration/.env" >&2; exit 1; }
  done

  BROKER_ID="$(jq -r '.id' "${OUTPUT_DIR}/service.json")"
  ENV_ID="$(jq -r '.environment_id' "${OUTPUT_DIR}/service.json")"

  BODY="$(mktemp)"; RESP="$(mktemp)"; trap 'rm -f "${BODY}" "${RESP}"' EXIT
  chmod 600 "${BODY}"
  jq -n \
    --arg name "${MI_NAME}" --arg broker "${BROKER_ID}" --arg env "${ENV_ID}" \
    --arg host "${CLOUD_SMF_HOST}" --arg vpn "${CLOUD_MSG_VPN}" \
    --arg cuser "${CLOUD_CONSUMER_USER}" --arg cpass "${CLOUD_CONSUMER_PASSWORD}" \
    --arg dburl "${DATABRICKS_URL}" --arg dbep "${DATABRICKS_SERVER_ENDPOINT}" \
    --arg dbid "${DATABRICKS_CLIENT_ID}" --arg dbsec "${DATABRICKS_CLIENT_SECRET}" \
    '
    {
      name: $name,
      description: "Solace -> Databricks Zerobus demo (created by cloud-setup/solace-cloud-api/micro-integration.sh)",
      microIntegrationType: "databricks-zerobus",
      direction: "target",
      brokerId: $broker,
      environmentId: $env,
      triggerDeployment: false,
      configurationValues: {
        "databricks-zerobus-vendor": {url: $dburl, serverEndpoint: $dbep, clientId: $dbid, clientSecret: $dbsec},
        "databricks-zerobus-solace": {authentication: {authenticationScheme: "AUTHENTICATION_SCHEME_BASIC", host: $host, messageVpn: $vpn, clientUsername: $cuser, clientPassword: $cpass}}
      }
    }' > "${BODY}"

  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    echo "DRY_RUN=1: request body that would be sent (secrets redacted), nothing sent:"
    redact < "${BODY}"
    exit 0
  fi

  echo "Creating Micro-Integration '${MI_NAME}' on service ${BROKER_ID} (environment ${ENV_ID})..."
  call POST "${API}" "${RESP}" -F "microIntegration=<${BODY};type=application/json"
  ( umask 077; cp "${RESP}" "${STATE_FILE}" )
  jq '.data | {id, name, state, brokerId, environmentId}' "${RESP}" | redact
  echo "Created. Next: $0 create-flow"
  ;;
create-flow)
  # shellcheck disable=SC1090
  source "${OUTPUT_DIR}/cloud-broker.env"
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/../../zerobus-integration/.env"
  for v in DATABRICKS_CATALOG DATABRICKS_SCHEMA DATABRICKS_TABLE; do
    [[ -n "${!v:-}" && "${!v}" != CHANGEME* ]] || { echo "${v} is not set in zerobus-integration/.env" >&2; exit 1; }
  done
  BODY="$(mktemp)"; RESP="$(mktemp)"; trap 'rm -f "${BODY}" "${RESP}"' EXIT
  jq -n \
    --arg name "${MI_FLOW_NAME}" --arg mi "$(mi_id)" \
    --arg queue "${CLOUD_QUEUE_NAME}" --arg dmq "${CLOUD_DMQ_NAME}" \
    --arg cat "${DATABRICKS_CATALOG}" --arg sch "${DATABRICKS_SCHEMA}" --arg tbl "${DATABRICKS_TABLE}" '
    {
      microIntegrationId: $mi,
      name: $name,
      description: "Queue -> Delta table (created by cloud-setup/solace-cloud-api/micro-integration.sh)",
      configurationValues: {
        "databricks-zerobus-solace-consumer": {binder: "solace", destination: $queue, endpointType: "QUEUE"},
        "databricks-zerobus-vendor-producer": {binder: "dbzerobus", destination: ($cat + "." + $sch + "." + $tbl), catalog: $cat, schema: $sch, table: $tbl},
        "databricks-zerobus-solace-dmq": {deadMessageQueue: {enabled: true, binder: "solace", destination: $dmq, destinationType: "QUEUE"}}
      }
    }' > "${BODY}"
  if [[ "${DRY_RUN:-0}" == 1 ]]; then
    echo "DRY_RUN=1: flow request body (nothing sent):"
    cat "${BODY}"
    exit 0
  fi
  echo "Creating flow '${MI_FLOW_NAME}' for Micro-Integration $(mi_id)..."
  call POST "${FLOW_API}" "${RESP}" -F "microIntegrationFlow=<${BODY};type=application/json"
  ( umask 077; cp "${RESP}" "${FLOW_FILE}" )
  jq '.data | {id, name, state, microIntegrationId}' "${RESP}" | redact
  echo "Created. Next: $0 deploy"
  ;;
deploy)
  TMP="$(mktemp)"; trap 'rm -f "${TMP}"' EXIT
  echo "Deploying $(mi_id)..."
  call PATCH "${API}/$(mi_id)/state" "${TMP}" -H "Content-Type: application/json" -d '{"state":"deploying"}'
  for _ in $(seq 1 60); do
    sleep 10
    show_state >/dev/null
    echo "  state: ${STATE}"
    [[ "${STATE}" == running || "${STATE}" == error || "${STATE}" == down ]] && break
  done
  show_state
  if [[ "${STATE}" == error ]]; then
    echo
    echo "The API gives no reason for 'error'. Known cause (17/10/2026): the broker's"
    echo "datacenter has no spare non-broker nodes to run the Micro-Integration on."
    echo "Ask Solace to check, or try a service in another datacenter. See"
    echo "docs/cloud-managed-micro-integration.md."
  fi
  ;;
status)
  show_state
  ;;
inspect)
  TMP="$(mktemp)"; trap 'rm -f "${TMP}"' EXIT
  echo "== Micro-Integration (GET, full record) =="
  call GET "${API}/$(mi_id)" "${TMP}" && redact < "${TMP}"
  echo "== Micro-Integration with latest deployment (list endpoint) =="
  call GET "${API}?ids=$(mi_id)&includeLatestDeployment=true" "${TMP}" && redact < "${TMP}"
  echo "== Flows =="
  call GET "${FLOW_API}?microIntegrationId=$(mi_id)" "${TMP}" && redact < "${TMP}"
  ;;
undeploy)
  TMP="$(mktemp)"; trap 'rm -f "${TMP}"' EXIT
  call PATCH "${API}/$(mi_id)/state" "${TMP}" -H "Content-Type: application/json" -d '{"state":"undeploying"}'
  echo "Undeploying requested. Check with: $0 status"
  ;;
delete)
  TMP="$(mktemp)"; trap 'rm -f "${TMP}"' EXIT
  if [[ -f "${FLOW_FILE}" ]]; then
    call DELETE "${FLOW_API}/$(jq -r '.data.id' "${FLOW_FILE}")" "${TMP}" || true
    rm -f "${FLOW_FILE}"
  fi
  call DELETE "${API}/$(mi_id)" "${TMP}"
  rm -f "${STATE_FILE}"
  echo "Deleted."
  ;;
esac
