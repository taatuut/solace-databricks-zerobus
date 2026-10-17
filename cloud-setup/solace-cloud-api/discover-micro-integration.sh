#!/usr/bin/env bash
# Looks up the Cloud-Managed Micro-Integration type for Databricks Zerobus
# and downloads its configuration templates, so the create script can be
# written against the real field names instead of guesses.
#
# Read-only: needs a token with the micro_integrations:get:* permission.
# Uses the (Beta) Micro-Integration API:
#   GET /api/v2/integration/microIntegrationTypes
#   GET /api/v2/integration/microIntegrationTypes/{id}/templates
#
# Usage:
#   ./discover-micro-integration.sh [name-filter]      (default: zerobus)
#
# Output (git-ignored, ../../output/):
#   mi-types.json                  matching Micro-Integration types
#   mi-templates-<type-id>.json    templates (schema of configurationValues)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1090
[[ -f "${SCRIPT_DIR}/.env" ]] && source "${SCRIPT_DIR}/.env"

command -v jq >/dev/null 2>&1 || { echo "jq is required (brew install jq)." >&2; exit 1; }
: "${SOLACE_CLOUD_API_TOKEN:?Set SOLACE_CLOUD_API_TOKEN in ${SCRIPT_DIR}/.env}"
: "${SOLACE_CLOUD_API_BASE:=https://api.solace.cloud/api/v2}"
FILTER="${1:-zerobus}"
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

echo "Looking up Micro-Integration types matching '${FILTER}'..."
api_get "${SOLACE_CLOUD_API_BASE}/integration/microIntegrationTypes?nameContains=${FILTER}" \
  "${OUTPUT_DIR}/mi-types.json"

COUNT=$(jq '.data | length' "${OUTPUT_DIR}/mi-types.json")
echo "Found ${COUNT} type(s):"
jq -r '.data[] | "  id=\(.id)  name=\(.name // "-")  direction=\(.direction // "-")"' \
  "${OUTPUT_DIR}/mi-types.json"
[[ "${COUNT}" -gt 0 ]] || { echo "No match. Try a different filter, e.g. 'databricks'." >&2; exit 1; }

for id in $(jq -r '.data[].id' "${OUTPUT_DIR}/mi-types.json"); do
  api_get "${SOLACE_CLOUD_API_BASE}/integration/microIntegrationTypes/${id}/templates" \
    "${OUTPUT_DIR}/mi-templates-${id}.json"
  echo
  echo "Templates for ${id} -> output/mi-templates-${id}.json"
  jq -r '.data[] | "  template id=\(.id)  templateType=\(.templateType)"' \
    "${OUTPUT_DIR}/mi-templates-${id}.json"
done

echo
echo "Done. Review the files in ${OUTPUT_DIR} (they contain no secrets)."
