#!/usr/bin/env bash
# Configures the local Solace broker for the Zerobus ingest demo via SEMP v2:
#   - Message VPN (+ SMF enabled)
#   - A Dead Message Queue (DMQ) -- REQUIRED by the Zerobus Micro-Integration;
#     without one, a NACKed message (e.g. a schema mismatch) is lost
#     permanently instead of landing somewhere inspectable.
#   - The ingest queue the Micro-Integration actually reads from, wired to
#     the DMQ above, with a topic subscription
#   - A scoped publisher client-username, restricted by ACL to the demo's
#     topic subtree
#   - A consumer client-username for the Micro-Integration (queue consume only)
#
# Field names are correct as of the current software broker release at
# time of writing, but SEMP is versioned per broker release -- validate
# against your broker's own "SEMP API browser" (Broker Manager > About >
# API Browser) before relying on this live.
#
# Usage: ./configure-local-broker.sh
# Requires: curl and a populated ../.env

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/../.env"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Missing ${ENV_FILE}. Copy local-broker/.env.example to local-broker/.env and fill it in first."
  exit 1
fi
# shellcheck disable=SC1090
source "${ENV_FILE}"

SEMP="${LOCAL_SEMP_HOST}/SEMP/v2/config"
AUTH=(-u "${LOCAL_SEMP_USER}:${LOCAL_SEMP_PASSWORD}")
VPN="${LOCAL_MSG_VPN}"
QUEUE="${ZEROBUS_QUEUE_NAME:-q-zerobus-ingest}"
DMQ="dmq-${QUEUE#q-}"
TOPIC="${ZEROBUS_TOPIC_SUBSCRIPTION:-zerobus-demo/sensor/>}"

semp() {
  # semp METHOD PATH [JSON_BODY]
  local method="$1" path="$2" body="${3:-}"
  local args=(-sS -X "${method}" "${AUTH[@]}" -H "content-type: application/json" "${SEMP}${path}")
  if [[ -n "${body}" ]]; then
    args+=(-d "${body}")
  fi
  local response
  response="$(curl "${args[@]}")"
  if echo "${response}" | grep -q '"code"'; then
    if echo "${response}" | grep -q '"code": *6001' || echo "${response}" | grep -q '"status": *"ALREADY_EXISTS"'; then
      echo "  (already exists, skipping) ${path}"
    else
      echo "  WARN on ${method} ${path}:"
      echo "${response}"
    fi
  fi
}

reassign_profile() {
  # reassign_profile USER -- needed when the user already exists with another
  # client profile; the change is applied with the user briefly disabled.
  semp PATCH "/msgVpns/${VPN}/clientUsernames/$1" '{"enabled":false}'
  semp PATCH "/msgVpns/${VPN}/clientUsernames/$1" "{\"clientProfileName\":\"${CLIENT_PROFILE}\"}"
  semp PATCH "/msgVpns/${VPN}/clientUsernames/$1" '{"enabled":true}'
}

echo "== 1. Message VPN '${VPN}' =="
semp POST "/msgVpns" "{\"msgVpnName\":\"${VPN}\",\"enabled\":true,\"maxMsgSpoolUsage\":1500}"
semp PATCH "/msgVpns/${VPN}" '{"serviceSmfPlainTextEnabled":true}'
semp PATCH "/msgVpns/${VPN}" '{"authenticationBasicEnabled":true,"authenticationBasicType":"internal"}'

echo "== 2. Dead Message Queue '${DMQ}' =="
semp POST "/msgVpns/${VPN}/queues" \
  "{\"queueName\":\"${DMQ}\",\"accessType\":\"exclusive\",\"permission\":\"consume\",\"ingressEnabled\":true,\"egressEnabled\":true,\"maxMsgSpoolUsage\":500}"

echo "== 3. Ingest queue '${QUEUE}' (wired to the DMQ above) =="
semp POST "/msgVpns/${VPN}/queues" \
  "{\"queueName\":\"${QUEUE}\",\"accessType\":\"exclusive\",\"permission\":\"consume\",\"ingressEnabled\":true,\"egressEnabled\":true,\"maxMsgSpoolUsage\":1500,\"deadMsgQueue\":\"${DMQ}\",\"maxRedeliveryCount\":3}"
semp POST "/msgVpns/${VPN}/queues/${QUEUE}/subscriptions" \
  "{\"subscriptionTopic\":\"${TOPIC}\"}"
echo "  ${QUEUE} <- subscribed to ${TOPIC}, dead messages -> ${DMQ}"

echo "== 3b. Client profile allowing guaranteed messaging =="
CLIENT_PROFILE="cp-zerobus"
semp POST "/msgVpns/${VPN}/clientProfiles" \
  "{\"clientProfileName\":\"${CLIENT_PROFILE}\",\"allowGuaranteedMsgSendEnabled\":true,\"allowGuaranteedMsgReceiveEnabled\":true,\"allowGuaranteedEndpointCreateEnabled\":true}"
semp PATCH "/msgVpns/${VPN}/clientProfiles/${CLIENT_PROFILE}" \
  '{"allowGuaranteedMsgSendEnabled":true,"allowGuaranteedMsgReceiveEnabled":true,"allowGuaranteedEndpointCreateEnabled":true}'

echo "== 4. Scoped publisher client-username =="
ACL="acl-${PUBLISHER_USER:-pub-zerobus}"
semp POST "/msgVpns/${VPN}/aclProfiles" \
  "{\"aclProfileName\":\"${ACL}\",\"clientConnectDefaultAction\":\"allow\",\"publishTopicDefaultAction\":\"disallow\",\"subscribeTopicDefaultAction\":\"disallow\"}"
semp POST "/msgVpns/${VPN}/aclProfiles/${ACL}/publishTopicExceptions" \
  "{\"publishTopicExceptionSyntax\":\"smf\",\"publishTopicException\":\"${TOPIC}\"}"
semp POST "/msgVpns/${VPN}/clientUsernames" \
  "{\"clientUsername\":\"${PUBLISHER_USER:-pub-zerobus}\",\"password\":\"${PUBLISHER_PASSWORD:-pub-zerobus-pw}\",\"enabled\":true,\"aclProfileName\":\"${ACL}\",\"clientProfileName\":\"${CLIENT_PROFILE}\"}"
reassign_profile "${PUBLISHER_USER:-pub-zerobus}"
echo "  ${PUBLISHER_USER:-pub-zerobus} -> may only publish on ${TOPIC}"

echo "== 5. Consumer client-username for the Zerobus Micro-Integration =="
CONSUMER="${CONSUMER_USER:-sub-zerobus}"
CONSUMER_ACL="acl-${CONSUMER}"
semp POST "/msgVpns/${VPN}/aclProfiles" \
  "{\"aclProfileName\":\"${CONSUMER_ACL}\",\"clientConnectDefaultAction\":\"allow\",\"publishTopicDefaultAction\":\"disallow\",\"subscribeTopicDefaultAction\":\"disallow\"}"
semp POST "/msgVpns/${VPN}/clientUsernames" \
  "{\"clientUsername\":\"${CONSUMER}\",\"password\":\"${CONSUMER_PASSWORD:-sub-zerobus-pw}\",\"enabled\":true,\"aclProfileName\":\"${CONSUMER_ACL}\",\"clientProfileName\":\"${CLIENT_PROFILE}\"}"
reassign_profile "${CONSUMER}"
echo "  ${CONSUMER} -> may only consume from queue ${QUEUE} (no direct publish/subscribe)"

cat <<INFO

Done. Next step: fill in zerobus-integration/application.yml (pointing its
Solace binder at this broker and queue '${QUEUE}') and start the
Micro-Integration -- see ../../zerobus-integration/README.md.
INFO
