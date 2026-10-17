# Solace -> Databricks Zerobus ingest demo

Demonstrates the **Solace Micro-Integration for Databricks Zerobus**:
events published to a Solace broker land directly in a Databricks Unity
Catalog managed Delta table, with no custom ETL job and no Kafka hop in
between.

> **Not an official Solace project.** This is a personal demo repository,
> provided as is, without warranty or support. Solace, PubSub+ and Databricks
> are trademarks of their respective owners. The Micro-Integration for
> Databricks Zerobus is a Beta product; details may change.

## Architecture at a glance

```
demo-apps/publisher.py  --publishes-->  local Solace broker (queue + DMQ)
                                              |
                                   Solace Micro-Integration
                                   for Databricks Zerobus
                                   (self-managed, Docker)
                                              |
                                              v
                                 Databricks Unity Catalog
                                 managed Delta table
```

A second path runs the same pipeline on a Solace Cloud broker with the
Cloud-Managed Micro-Integration, set up by script from `cloud-setup/` —
see [`cloud-setup/README.md`](cloud-setup/README.md). The local path above
stays as it is.

**New here? Follow [`docs/runbook.md`](docs/runbook.md)**: complete, ordered
steps for both paths, including the Databricks permissions needed.

## Prerequisites

- Docker Desktop (for the local Solace broker and the Micro-Integration
  container).
- A Databricks workspace with Unity Catalog enabled (the AWS default) or
  a Premium-tier workspace (required on Azure), not a compliance-security-
  profile workspace (FedRAMP/HIPAA/PCI-DSS), in a Zerobus-supported
  region.
- A Databricks service principal (OAuth client ID + secret, scope
  `all-apis`, 90-day secret) with `USE CATALOG`, `USE SCHEMA`, and
  `MODIFY, SELECT` granted on the target table, and nothing more. A
  workspace admin must create it; see the permissions table in
  [`docs/runbook.md`](docs/runbook.md).
- A pre-created target Delta table (Unity Catalog managed, ASCII-only
  column names) — the Micro-Integration does not create it for you.
- Outbound network access on TLS 1.2+ from wherever the Micro-Integration
  runs to the Databricks workspace, with no proxy in between (a proxy
  that strips HTTP/2 headers breaks the gRPC connection Zerobus uses).

## Step by step: from zero to a running demo

### 1. Set up Databricks

See [`docs/zerobus-integration.md`](docs/zerobus-integration.md) for the
full prerequisite checklist (table, service principal, grants).
[`docs/databricks-setup.md`](docs/databricks-setup.md) is the Azure console
walk-through.

### 2. Start and configure the local broker

```bash
cd local-broker
./docker-run.sh
cp .env.example .env   # fill in real values
./semp/configure-local-broker.sh
```

### 3. Configure and start the Zerobus Micro-Integration

```bash
cd zerobus-integration
cp application.yml.example application.yml   # fill in real values, never commit this file
cp .env.example .env
docker compose up
```

See [`zerobus-integration/README.md`](zerobus-integration/README.md) for
what each property means.

### 4. Run the demo data producer

```bash
cd demo-apps
pip install -r requirements.txt
python publisher.py
```

Then confirm the rows arrive in Databricks (`SELECT * FROM
<catalog>.<schema>.<table> ORDER BY event_time DESC LIMIT 20`).

## Troubleshooting

See [`docs/notes-and-gotchas.md`](docs/notes-and-gotchas.md). Also check the Micro-Integration's own Actuator health
endpoint and its container logs first — most failures at this stage are
either a missing DMQ, a schema mismatch between the JSON payload and the
Delta table, or a service-principal permission that wasn't granted.

## Further reading

[`docs/runbook.md`](docs/runbook.md) (setup from scratch),
[`docs/notes-and-gotchas.md`](docs/notes-and-gotchas.md) (constraints and
problems already solved), [`docs/topology.md`](docs/topology.md) and
[`docs/presentation-notes.md`](docs/presentation-notes.md).

## License

Apache License 2.0, see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE). The
license covers the files in this repository only, not the Solace and
Databricks products it integrates with.

## Language

Documentation is in English.
