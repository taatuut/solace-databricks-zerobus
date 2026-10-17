#!/usr/bin/env bash
# Creates one Solace Cloud event broker service via the Mission Control REST API.
# Optional automation -- the console wizard works equally well and is
# recommended the first time you do this. See:
#   https://docs.solace.com/Cloud/ght_use_rest_api_services.htm
#   https://api.solace.dev/cloud/reference/createservice
#
# Usage:
#   ./create-service.sh <name> <datacenterId> <serviceClassId> <msgVpnName>
#
# Example:
#   ./create-service.sh my-demo-service  aws-us-east-1  DEVELOPER  my-demo
#
# Run `curl -s -H "Authorization: Bearer $SOLACE_CLOUD_API_TOKEN" \
#   "$SOLACE_CLOUD_API_BASE/missionControl/datacenters"` first to look up the
# exact datacenterId values available to your account/org -- they change
# over time and differ per contract, so do not hard-code them blindly.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env"

NAME="${1:?name required}"
DATACENTER_ID="${2:?datacenterId required}"
SERVICE_CLASS_ID="${3:?serviceClassId required, e.g. DEVELOPER}"
MSG_VPN_NAME="${4:?msgVpnName required}"

: "${SOLACE_CLOUD_API_TOKEN:?Set SOLACE_CLOUD_API_TOKEN (see .env.example)}"
: "${SOLACE_CLOUD_API_BASE:=https://api.solace.cloud/api/v2}"

curl -sS -X POST "${SOLACE_CLOUD_API_BASE}/missionControl/eventBrokerServices" \
  -H "Authorization: Bearer ${SOLACE_CLOUD_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"${NAME}\",
    \"datacenterId\": \"${DATACENTER_ID}\",
    \"serviceClassId\": \"${SERVICE_CLASS_ID}\",
    \"msgVpnName\": \"${MSG_VPN_NAME}\",
    \"eventBrokerVersion\": \"current\"
  }" | tee /dev/stderr

echo
echo "Response is 202 Accepted -- creation is asynchronous. Poll GET"
echo "  ${SOLACE_CLOUD_API_BASE}/missionControl/eventBrokerServices"
echo "until status is 'completed', then fetch connection details (SMF host,"
echo "port 55443, VPN name) from the service's 'connectionEndPoints'."
