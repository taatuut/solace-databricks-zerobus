#!/usr/bin/env bash
# Read-only: lists what is needed to fill terraform.tfvars -- the available
# datacenters and service classes, plus the event broker services that
# already exist in the organization. Do not hard-code datacenter ids from
# old notes; they are account/contract specific and change over time.
#
# Usage: ./lookup-service-options.sh
# Output (git-ignored, ../../output/): datacenters.json, service-classes.json,
# services.json

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env"

command -v jq >/dev/null 2>&1 || { echo "jq is required (brew install jq)." >&2; exit 1; }
: "${SOLACE_CLOUD_API_TOKEN:?Set SOLACE_CLOUD_API_TOKEN in ${SCRIPT_DIR}/.env}"
: "${SOLACE_CLOUD_API_BASE:=https://api.solace.cloud/api/v2}"
OUTPUT_DIR="${SCRIPT_DIR}/../../output"
mkdir -p "${OUTPUT_DIR}"

api_get() {
  local url="$1" out="$2" code
  code=$(curl -sS -o "${out}" -w '%{http_code}' \
    -H "Authorization: Bearer ${SOLACE_CLOUD_API_TOKEN}" "${url}")
  if [[ "${code}" != 2* ]]; then
    echo "GET ${url} -> HTTP ${code}" >&2
    cat "${out}" >&2; echo >&2
    exit 1
  fi
}

api_get "${SOLACE_CLOUD_API_BASE}/missionControl/datacenters" "${OUTPUT_DIR}/datacenters.json"
api_get "${SOLACE_CLOUD_API_BASE}/missionControl/serviceClasses" "${OUTPUT_DIR}/service-classes.json"
api_get "${SOLACE_CLOUD_API_BASE}/missionControl/eventBrokerServices" "${OUTPUT_DIR}/services.json"

echo "== Datacenters (id, provider, type, location) =="
jq -r '.data[] | "  \(.id)\t\(.provider // "-")\t\(.datacenterType // "-")\t\(.name // .location // "-")"' \
  "${OUTPUT_DIR}/datacenters.json"
echo
echo "== Service classes =="
jq -r '.data[] | "  \(.id // .serviceClassId // "-")\t\(.name // .displayedAttributes.name // "-")"' \
  "${OUTPUT_DIR}/service-classes.json" 2>/dev/null || jq . "${OUTPUT_DIR}/service-classes.json"
echo
echo "== Existing event broker services =="
jq -r '.data[] | "  \(.id)\t\(.name)\t\(.datacenterId // "-")\t\(.serviceClassId // "-")\t\(.creationState // .adminState // "-")"' \
  "${OUTPUT_DIR}/services.json"
echo
echo "Full responses are in ${OUTPUT_DIR} (they contain no secrets)."
