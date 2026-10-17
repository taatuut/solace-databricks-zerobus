# Solace Cloud platform broker + Cloud-Managed Micro-Integration

This folder holds the automation for the second deployment path of the
demo: a Solace Cloud event broker service with a **Cloud-Managed**
Solace Micro-Integration for Databricks Zerobus. It runs in parallel to
the local path (`../local-broker/` + `../zerobus-integration/`, a Docker
broker and a self-managed Micro-Integration), which stays as it is.

The goal is that everything after creating the API token is done by
script, with no work in the Solace Cloud Console UI. The structure
follows the `cloud-setup/` of the `dadd-2026-solace-stackit-soevereine-
cloud` repo:

- `terraform/` creates the event broker service (Mission Control level,
  `solacecloud` provider, values in a git-ignored `terraform.tfvars`).
- `solace-cloud-api/` holds REST scripts and the git-ignored `.env`
  with the API token. Scripts that configure objects *inside* a broker
  (queues, client usernames) use that broker's own SEMP API with the
  manager credentials from the Terraform state, not the API token.
- Script output goes to `../output/` (git-ignored).

Complete step-by-step for both paths: [`../docs/runbook.md`](../docs/runbook.md).

## Prerequisites

- A Solace Cloud account with the Micro-Integration Manager role, and
  Micro-Integrations enabled for the account (accounts include a set
  number of them).
- `curl` and `jq` (`brew install jq`), and for the Terraform step the
  `terraform` CLI (>= 1.5).
- The Databricks side from `../docs/databricks-setup.md` (table,
  service principal, grants) is shared with the local path.

## The one manual step: the API token

Creating an API token cannot be scripted. In the Solace Cloud Console:
user menu, **Token Management**, **Create Token**. Give it:

- permission to read and create services (Mission Control), and
- `micro_integrations:*:*` for the Micro-Integration API (read-only
  calls need only `micro_integrations:get:*`).

The API base URL must match the Home Cloud region of the
organization that owns the token: `https://api.solace.cloud/api/v2` (US
East), `https://api.solacecloud.eu/api/v2` (EU),
`https://api.solacecloud.com.au/api/v2` (AU) or
`https://api.solacecloud.sg/api/v2` (SG). The organization used for this
demo is on US East: the EU URL answered `401 Your permissions have
changed` for the same token. (The datacenter of the broker service you
create can still be in Europe; the base URL only decides which API
endpoint is called.) Put both values in `solace-cloud-api/.env` (copy
from `.env.example`). Never commit the token or paste it in a chat.

## Order of operations

Shortcut for steps 3 to 6 below, after the token and
`terraform/terraform.tfvars` are in place: `./setup-cloud.sh preflight`,
then `./setup-cloud.sh up` (`status` shows the Micro-Integration state,
`down` removes everything again, `--yes` skips the Terraform prompts).
Details in [`../docs/runbook.md`](../docs/runbook.md). The script is new
and not yet tested end to end; the manual steps below are the reference
path.

All commands run from `cloud-setup/solace-cloud-api/` unless noted, in a
normal terminal (the scripts call the Solace Cloud and broker endpoints).

1. `./discover-micro-integration.sh`: find the type id of the Zerobus
   Micro-Integration and download its configuration templates
   (read-only). Result: type `databricks-zerobus-target`, see
   [`../docs/cloud-managed-micro-integration.md`](../docs/cloud-managed-micro-integration.md).
2. `./lookup-service-options.sh`: list datacenters, service classes and
   existing services, to fill `terraform/terraform.tfvars` (copy the
   example). Pick a datacenter that has spare non-broker capacity.
3. Create the service, from `terraform/`: `./run-terraform.sh init`, then
   `plan` and `apply`. About 5 minutes.
4. `./show-service-connection.sh` and `./get-service-endpoints.sh`: write
   the connection data (with the manager credential) to `../../output/`
   (git-ignored).
5. `./configure-cloud-broker.sh`: client profile, queue, DMQ, publisher
   and consumer users with generated passwords, and the CA certificates
   for TLS clients. Idempotent.
6. `./micro-integration.sh create`, `create-flow`, `deploy`: the
   Micro-Integration, its flow and the deployment. The Databricks values
   are read from `../zerobus-integration/.env`, shared with the local path.
   `status` and `inspect` show the state, `undeploy` and `delete` remove it.
7. Test end to end: from `demo-apps/`, `python publisher.py --target cloud`,
   then query the Delta table.

Details that cost time (see the doc above): the API base URL must match
the token's Home Cloud, a failed deploy gives no reason through the API or
the Console error log (check View Logs once it has run, and the
datacenter's capacity), and the flow's `destination` must hold the full
table name.

The Micro-Integration API is Beta and its Zerobus type is not documented
in the API reference, so details may change.
