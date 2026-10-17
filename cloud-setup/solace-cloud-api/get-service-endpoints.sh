#!/usr/bin/env bash
# Reads the connection endpoints (SMF, SEMP, REST, ...) of the Terraform-
# managed service from the Mission Control API: Terraform's output does not
# carry them. Prints the response with password/secret/token keys redacted
# and writes it to ../../output/service-endpoints.json (git-ignored).
#
# Needs ../../output/service.json from ./show-service-connection.sh (for the
# service id) and the token in .env. Read-only.
#
# Usage: ./get-service-endpoints.sh

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env"
OUTPUT_DIR="${SCRIPT_DIR}/../../output"

command -v jq >/dev/null 2>&1 || { echo "jq is required (brew install jq)." >&2; exit 1; }
: "${SOLACE_CLOUD_API_TOKEN:?Set SOLACE_CLOUD_API_TOKEN in ${SCRIPT_DIR}/.env}"
: "${SOLACE_CLOUD_API_BASE:=https://api.solace.cloud/api/v2}"
[[ -f "${OUTPUT_DIR}/service.json" ]] || { echo "Run ./show-service-connection.sh first." >&2; exit 1; }

SERVICE_ID="$(jq -r '.id' "${OUTPUT_DIR}/service.json")"
OUT="${OUTPUT_DIR}/service-endpoints.json"

code=$(curl -sS -o "${OUT}" -w '%{http_code}' \
  -H "Authorization: Bearer ${SOLACE_CLOUD_API_TOKEN}" \
  "${SOLACE_CLOUD_API_BASE}/missionControl/eventBrokerServices/${SERVICE_ID}?expand=serviceConnectionEndpoints")
chmod 600 "${OUT}"
if [[ "${code}" != 2* ]]; then
  echo "GET service ${SERVICE_ID} -> HTTP ${code}" >&2
  cat "${OUT}" >&2; echo >&2
  exit 1
fi

jq '
  def redact:
    walk(if type == "object"
         then with_entries(if (.key | test("password|secret|token"; "i")) then .value = "<redacted>" else . end)
         else . end);
  .data | redact
' "${OUT}"
echo
echo "Unredacted copy: ${OUT} (git-ignored, keep it local)."
