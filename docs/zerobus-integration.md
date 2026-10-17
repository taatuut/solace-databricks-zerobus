# Zerobus integration: prerequisites and configuration

This is the detailed companion to `zerobus-integration/README.md` —
everything to get right on the Databricks side *before* starting the
Micro-Integration, plus what each configuration property means. Facts
below are drawn from Solace's own documentation (linked in
[`notes-and-gotchas.md`](notes-and-gotchas.md));
this is a Beta connector, so re-verify anything surprising against the
current docs rather than assuming this stays accurate indefinitely.

## Databricks-side prerequisites

1. **Workspace**: Unity Catalog enabled (the default for new AWS
   workspaces) or a Premium-tier workspace (required on Azure).
   Compliance security profile workspaces (FedRAMP, HIPAA, PCI-DSS) are
   not supported. The workspace and the target table must be in the same
   Zerobus-supported region.
2. **Target table**: a Unity Catalog **managed** Delta table, created
   before starting the Micro-Integration — it does not create tables
   itself. DBFS root storage, external tables, and private-endpoint
   storage are not supported. Use only ASCII letters, digits, and
   underscores in the table name and every column name. Add new columns
   before sending records that use them. Don't recreate or drop the table
   while the integration is running. Matching `demo-apps/`'s sample
   payload, a starting DDL:
   ```sql
   CREATE TABLE <catalog>.<schema>.<table> (
     device_id     STRING,
     reading_type  STRING,
     value         DOUBLE,
     unit          STRING,
     event_time    TIMESTAMP
   );
   ```
3. **Service principal**: create one in the Databricks workspace, note
   its **Application ID** (this is `databricks.clientId`) and generate a
   **client secret** (shown once — this is `databricks.clientSecret`;
   store it immediately in a password manager or this repo's gitignored
   `.env`/`application.yml`, never anywhere else).
4. **Grants** (in Databricks SQL, on the service principal): `USE
   CATALOG` on the catalog, `USE SCHEMA` on the schema, and `MODIFY,
   SELECT` on the target table specifically — don't grant broader access.

## Solace-side prerequisites

1. A queue dedicated to this integration (e.g. `q-zerobus-ingest`), with
   subscriptions matching the topic(s) the demo publishes on.
2. **A Dead Message Queue (DMQ) configured on that queue.** Without one,
   a message that the Micro-Integration NACKs (e.g. a schema mismatch) is
   lost permanently rather than landing somewhere inspectable.

## Configuring `zerobus-integration/application.yml`

The Micro-Integration is configured Spring Cloud Stream-style, under
`spring.cloud.stream.*`, plus a `databricks.*` block at the root (see
`application.yml.example` for a filled-in skeleton). The `databricks.*`
properties and the binder-level `...environment.solace.java.host`
property below are confirmed against Solace's own docs; the exact names
of the other Solace connection properties (VPN, client username/password)
and the binder/binding key names were not shown on the pages fetched
while building this template (they live on a separate "Step 1:
Connecting to Your Event Broker" page) — treat those as a best-effort
reconstruction and verify them against that page before relying on this
live.

- `spring.cloud.stream.binders.solace.environment.solace.java.host` — the
  Solace broker's SMF host, e.g. `tcp://localhost:55554` for the local
  broker.
- `spring.cloud.stream.bindings.input-1.destination` — the source queue
  name.
- `databricks.url` — the workspace URL, e.g.
  `https://<workspace-id>.cloud.databricks.com`.
- `databricks.serverEndpoint` — the Zerobus gRPC endpoint (includes the
  workspace ID and region — get the exact value from the Databricks
  workspace/Zerobus setup UI, don't guess it from the workspace URL).
- `databricks.clientId` / `databricks.clientSecret` — the service
  principal's OAuth credentials.
- `spring.cloud.stream.dbzerobus.bindings.output-1.producer.{catalog,
  schema,table}` — the target table, per workflow (or supply the full
  `catalog.schema.table` as the destination instead). Shared values can
  go under `spring.cloud.stream.dbzerobus.default.producer.` instead of
  repeating them per workflow.

## Data format and delivery semantics

- Payloads must be UTF-8 JSON; Zerobus validates them server-side against
  the live Delta table schema.
- Delivery is **at-least-once**, with no built-in deduplication — add a
  dedup key/column downstream if the demo needs to claim exactly-once.
- A per-event header, `scst_targetDestination`, can route events to
  different tables at runtime if the demo ever needs to fan out to more
  than one table from a single workflow.

## Troubleshooting

- Health/metrics are exposed via an Actuator endpoint, per workflow and
  per Databricks table stream — check that first.
- A retriable error (network timeout, rate limiting) triggers automatic
  stream recovery with backoff — expect transient WARN-level noise on
  startup if Databricks isn't reachable yet.
- A non-retriable error (table not found, schema mismatch) NACKs the
  message to the DMQ — check the DMQ, not just the Micro-Integration's
  logs, when messages seem to vanish.

### Problems met while bringing this up (16/10/2026)

| Symptom | Cause | Fix |
| --- | --- | --- |
| `At least 1 workflow must be enabled` at start | `application.yml` not in the Micro-Integration's format | Use `solace.java.*`, `solace.connector.workflows.0.enabled: true`, `input-0`/`output-0` (see `application.yml.example`) |
| `NullPointerException` in `MicroIntegrationTopologyFactory` | `output-0` has no `binder` | Set `binder: dbzerobus` on `output-0` |
| `Scopes 'all-apis' are not assigned to the client` (403) | Databricks OAuth client lacks the scope | Admin issues a new secret on the service principal page; test with a direct `curl` to `/oidc/v1/token` |
| Container up but nothing listening, log silent after the banner | Local broker not running; the Solace client retries forever (`connect-retries: -1`) | Start the broker; check `docker ps` |
| `Capability Mismatch: Router does not support guaranteed subscriber flows` | VPN `default` client profile disallows guaranteed messaging | `cp-zerobus` profile in `configure-local-broker.sh` |
| Health check returns nothing / connection reset | Actuator is on container port 8090 (compose maps `8081:8090`) and returns 401 without a user | Define `SOLACE_CONNECTOR_SECURITY_USERS_0_NAME/PASSWORD` and call with `curl -u` |
| `Record decoder/encoder error: invalid digit found in string` (error 4044), events land in the DMQ | `event_time` sent as ISO text for a `TIMESTAMP` column | Send epoch microseconds as a number |

The default log level shows only warnings. To see why a write fails,
enable the `logging.level` block in `application.yml` (commented out in
the example) and restart the container.

