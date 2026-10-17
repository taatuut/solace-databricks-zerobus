#!/usr/bin/env bash
# Starts a local, single-availability, self-managed Solace PubSub+ software
# broker (standard edition) for the Solace -> Databricks Zerobus ingest demo.
#
# Notes:
# - SMF (messaging) is mapped to host port 55554 instead of the default
#   55555, because 55555 is sometimes already taken on macOS. If 55555 is
#   free on your machine, feel free to map it 1:1 instead and update
#   local-broker/.env.
# - --restart unless-stopped: the broker comes back after a Docker Desktop
#   or Mac restart. The container's own filesystem survives a restart, so
#   the VPN, queues and users stay configured; there is no need to re-run
#   semp/configure-local-broker.sh. Only removing the container
#   (docker rm -f) wipes the config; there is no bind-mounted
#   /var/lib/solace.
# - Requirements: Docker Desktop with >= 4-8 GB RAM assigned and ~6 GB free
#   disk.
#
# Docs: https://docs.solace.com/Software-Broker/SW-Broker-Set-Up/Containers/Set-Up-Docker-Container-Linux.htm

set -euo pipefail

CONTAINER_NAME="zerobus-demo-local-broker"
IMAGE="solace/solace-pubsub-standard"

if docker ps -a --format '{{.Names}}' | grep -qx "${CONTAINER_NAME}"; then
  echo "Container '${CONTAINER_NAME}' already exists. Remove it first with:"
  echo "  docker rm -f ${CONTAINER_NAME}"
  exit 1
fi

docker run -d \
  --name "${CONTAINER_NAME}" \
  --restart unless-stopped \
  --shm-size=2g \
  --ulimit nofile=2448:1048576 \
  -p 55554:55555 \
  -p 8080:8080 \
  -p 8008:8008 \
  -p 1883:1883 \
  -p 5672:5672 \
  -p 9000:9000 \
  --env username_admin_globalaccesslevel=admin \
  --env username_admin_password=admin \
  "${IMAGE}"

echo "Waiting for the broker's SEMP management API to come up..."
until curl -s -o /dev/null -u admin:admin "http://localhost:8080/SEMP/v2/config/about/user"; do
  sleep 2
done

cat <<INFO

Broker '${CONTAINER_NAME}' is up.
  Broker Manager (SEMP)  : http://localhost:8080   (admin/admin)
  SMF (messaging)        : tcp://localhost:55554
  Web messaging          : ws://localhost:8008
  MQTT                   : tcp://localhost:1883
  AMQP                   : amqp://localhost:5672

Next step: local-broker/semp/configure-local-broker.sh
INFO
