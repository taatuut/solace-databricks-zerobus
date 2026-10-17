# Platform broker setup (Solace Cloud)

The Solace Cloud broker and the Cloud-Managed Micro-Integration run in
parallel to the local Docker path. Everything after creating an API token
is scripted; see [`../cloud-setup/README.md`](../cloud-setup/README.md) for
the order of operations and
[`cloud-managed-micro-integration.md`](cloud-managed-micro-integration.md)
for what the Micro-Integration API accepts and the problems met.

## Provisioning

The service is created with Terraform (`cloud-setup/terraform/`, run
through `run-terraform.sh`, which takes the token from
`cloud-setup/solace-cloud-api/.env`). `solace-cloud-api/create-service.sh`
and the console are manual alternatives. The datacenter of a service can
not be changed afterwards: switching region means destroying the service
and creating a new one (see the Terraform README).

## Capacity of the datacenter

A managed Micro-Integration runs on non-broker nodes of the broker's
datacenter. A datacenter without spare nodes accepts the broker but
cannot run the Micro-Integration, and the failure shows up only as
`error` after about 10 minutes (17/10/2026: `aks-eastus`). Ask Solace to
check a datacenter first if a deploy ends in `error` without a reason.

## Network access

A public cluster is the deliberate demo-only simplification used here
(same as the local broker's exposed ports) — a production setup would use
private networking (VPC peering, PrivateLink, or the provider's
equivalent) between the broker and the Micro-Integration.

## Credentials

The broker's management credential comes from the Terraform output
(`show-service-connection.sh`, written to the git-ignored `output/`). The
client usernames for the publisher and the Micro-Integration get generated
passwords (`output/cloud-broker.env`). Mission Control does not return the
management credentials through a plain GET, see [`notes-and-gotchas.md`](notes-and-gotchas.md).
