# Notes and gotchas

Facts and constraints to know before changing anything, plus small
problems met while building this demo. The connector is Beta, so
re-check surprising details against Solace's current documentation:
[Databricks Zerobus overview](https://docs.solace.com/Micro-Integrations/Self-Managed/Databricks-Zerobus/Databricks-Zerobus-Overview.htm),
[configuring connection details](https://docs.solace.com/Micro-Integrations/Self-Managed/Databricks-Zerobus/Databricks-Zerobus-Configuring-Connection-Details.htm),
[integration hub page](https://solace.com/integration-hub/databricks-zerobus-ingest/).

## Architecture facts

- **The target Delta table must already exist and be Unity Catalog
  managed.** The Micro-Integration does not create tables. DBFS root
  storage, external tables and private-endpoint storage are not
  supported. Don't recreate or drop the table while the integration runs.
- **Table and column names: ASCII letters, digits and underscores
  only.** Add new columns before sending records that use them; the
  integration does not evolve the schema, and Zerobus validates records
  server-side against the existing Delta schema.
- **A dead message queue (DMQ) must be configured on the Solace queue
  before deployment.** Non-retriable errors (table not found, schema
  mismatch) NACK the message to the DMQ; without one the message is lost.
- **Delivery is at-least-once, with no built-in deduplication.** If a
  demo needs exactly-once, deduplicate downstream (for example a key
  column plus a view).
- **No proxy between the Micro-Integration and Databricks.** The
  connection is gRPC (HTTP/2); a proxy that strips HTTP/2 headers breaks
  it. Outbound TLS 1.2+ must be allowed directly.
- **Workspace requirements:** on Azure a Premium workspace; on AWS Unity
  Catalog enabled. Compliance security profile workspaces (FedRAMP,
  HIPAA, PCI-DSS) are not supported. Workspace and table must be in the
  same Zerobus-supported region.
- **Authentication is OAuth 2.0 client credentials** through a Databricks
  service principal. The principal needs `USE CATALOG`, `USE SCHEMA` and
  `MODIFY, SELECT` on the table, granted in Databricks SQL (see
  [`runbook.md`](runbook.md)).
- **Configuration is Spring Cloud Stream-style `application.yml`.** Treat
  a filled-in `application.yml` like a `.env` file and never commit it.
- **Zerobus JSON needs `TIMESTAMP` values as epoch microseconds**, not
  ISO text (see [`demo-apps.md`](demo-apps.md)).
- **Cloud-Managed Micro-Integrations need spare non-broker capacity in
  the broker's datacenter**, and the flow's producer `destination` must be
  the full `catalog.schema.table` (see
  [`cloud-managed-micro-integration.md`](cloud-managed-micro-integration.md)).

## Secrets

`local-broker/.env`, `zerobus-integration/.env`,
`zerobus-integration/application.yml`, `cloud-setup/solace-cloud-api/.env`,
`cloud-setup/terraform/terraform.tfvars` and Terraform state files are
git-ignored and must never be committed. Example files hold only
`CHANGEME` placeholders. Screenshots show real workspace and user
identifiers, so only redacted copies named `<name>-redacted.<ext>` in
`docs/images/` are committed (see `.gitignore`); redact first, then
reference only the redacted file. Before publishing a
fork or a change, scan the full git history, not just the current files:
a file once committed and later removed is still retrievable.

## Gotchas

### Terraform CLI on macOS (Homebrew)

`brew install terraform` fails since HashiCorp moved Terraform to the BUSL
license (the formula was removed from homebrew-core). Use HashiCorp's tap:

```bash
brew install hashicorp/tap/terraform
terraform version
```

### `mktemp` on macOS: put the `X`s at the very end

BSD `mktemp` only randomizes a run of `X`s at the very end of the name.
`mktemp ".../name.XXXXXX.json"` creates the literal path once, then fails
forever with `File exists`. Use `mktemp ".../name.json.XXXXXX"`.

### Mission Control API does not return broker-management credentials

`GET .../missionControl/eventBrokerServices/{id}` (even with `expand=...`)
returns no management credentials. The `solacecloud` Terraform provider
does expose them as
`message_vpn.manager_management_credential.{username,password}`, so read
them from `terraform output -json service` (see
`cloud-setup/solace-cloud-api/show-service-connection.sh`).

### Shell comments when copy-pasting

zsh (the macOS default) does not treat `#` as a comment on the same line
as a command when pasted interactively. Keep comments on their own line.
