#!/usr/bin/env bash
# Prints the connection details of the Terraform-managed Solace Cloud
# service with secrets redacted (any key whose name contains password,
# secret or token), so the output is safe to share. The full, unredacted
# data is written to ../../output/service.json (git-ignored, mode 600) for
# the scripts that need the broker's management credentials.
#
# Usage: ./show-service-connection.sh [terraform-output-name]   (default: service)
# Requires: terraform, jq, and an applied ../terraform/.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/../../output"
NAME="${1:-service}"
mkdir -p "${OUTPUT_DIR}"

command -v jq >/dev/null 2>&1 || { echo "jq is required (brew install jq)." >&2; exit 1; }

( umask 077; "${SCRIPT_DIR}/../terraform/run-terraform.sh" output -json "${NAME}" > "${OUTPUT_DIR}/service.json" )

jq '
  def redact:
    walk(if type == "object"
         then with_entries(if (.key | test("password|secret|token"; "i")) then .value = "<redacted>" else . end)
         else . end);
  redact
' "${OUTPUT_DIR}/service.json"

echo
echo "Unredacted copy: ${OUTPUT_DIR}/service.json (git-ignored, keep it local)."
