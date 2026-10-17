# Runbook: set up and run the demo from scratch

This is the one document to follow if you have never seen this repo. It
covers both ways of running the demo, which share the same Databricks
side and the same publisher:

| | Path A: local | Path B: Solace Cloud |
| --- | --- | --- |
| Broker | Docker container on your laptop | Solace Cloud event broker service |
| Micro-Integration | self-managed, Docker container | Cloud-Managed, deployed through the API |
| Set up with | `local-broker/`, `zerobus-integration/` | `cloud-setup/` (scripted) |
| Publisher | `python publisher.py` | `python publisher.py --target cloud` |

Do Part 1 (Databricks) once. Then do Path A, Path B or both. Both paths
write to the same Delta table with the same service principal.

Screenshots are in `docs/images/` and are git-ignored (they show real
workspace and user identifiers), so on a fresh clone the image links are
broken; the text stands on its own.

## Part 1. Databricks (once)

### 1.1 Permissions: who needs what

Three different people or identities are involved. The most common
reason for a failed setup is a missing permission, so check this first.

| Who | Needs | For |
| --- | --- | --- |
| You (set-up person) | permission to create a SQL warehouse (or use an existing one), `USE CATALOG` on the catalog, `USE SCHEMA` and `CREATE TABLE` on the schema | creating the target table; you become its owner |
| Workspace admin | workspace admin rights | creating the service principal and its OAuth secret (the *service principal manager* role can not create a secret). Also granting `USE CATALOG`/`USE SCHEMA` if you are not owner or `MANAGE` holder |
| Service principal (used by the Micro-Integration) | exactly the three grants below | writing events to the table |

The service principal needs only these privileges:

| Level | Privilege | Why |
| --- | --- | --- |
| Catalog | `USE CATALOG` | resolve the catalog |
| Schema | `USE SCHEMA` | resolve the schema |
| Table | `MODIFY` and `SELECT`, both granted explicitly | Zerobus writes rows to the table |

Not needed: `MANAGE`, `CREATE TABLE`, `READ METADATA`, privileges on
other tables. (This demo's service principal also holds `MANAGE` and
`READ METADATA` on its schema; that was left in place on
purpose and is more than required. Remove it outside a demo.)

The OAuth secret must carry the scope `all-apis`. A secret created
through the admin on the service principal's own page does; one that
did not gave `Scopes 'all-apis' are not assigned to the client` (403).
The secret is valid for 90 days: put a reminder in your calendar a week
before it expires (rotation steps in
[`databricks-setup.md`](databricks-setup.md), section 8).

### 1.2 Workspace requirements

Unity Catalog enabled, Premium tier on Azure, no compliance security
profile, and a Zerobus-supported region (the demo uses Azure East US).
Console walk-through with screenshots:
[`databricks-setup.md`](databricks-setup.md), section 1.

### 1.3 Create the SQL warehouse, schema and table

In the SQL Editor (warehouse `zerobus-demo`, 2X-Small serverless; see
`databricks-setup.md` sections 2-3). The demo uses the existing schema
`<catalog>.default`, so no schema needs creating (use a schema you can
create tables in):

```sql
CREATE TABLE <catalog>.default.zerobus_demo_events (
  device_id     STRING,
  reading_type  STRING,
  value         DOUBLE,
  unit          STRING,
  event_time    TIMESTAMP
);
```

It must be a Unity Catalog **managed** Delta table with ASCII-only
names; check with `DESCRIBE TABLE EXTENDED` (`Type` = `MANAGED`,
`Provider` = `delta`).

### 1.4 Service principal and grants

1. Ask a workspace admin to create a Databricks-managed service
   principal and generate an OAuth secret on its **Secrets** tab (90 days).
   You receive the **application (client) ID** and the **secret** (shown
   once; send it through a private channel, store it in a password
   manager, never in the repo or a chat).
2. Run the grants (as table owner and as catalog/schema owner or an admin):

   ```sql
   GRANT USE CATALOG ON CATALOG <catalog> TO `<application-id>`;
   GRANT USE SCHEMA ON SCHEMA <catalog>.default TO `<application-id>`;
   GRANT MODIFY, SELECT ON TABLE <catalog>.default.zerobus_demo_events TO `<application-id>`;
   ```

   `PERMISSION_DENIED: User does not have MANAGE on ...` means you are
   not an owner: ask the owner or an admin to run the first two.

### 1.5 Fill in `zerobus-integration/.env`

Both paths read the Databricks values from this git-ignored file:

```bash
cd zerobus-integration
cp .env.example .env
```

Set `DATABRICKS_URL` (workspace URL), `DATABRICKS_SERVER_ENDPOINT`
(`https://<workspace-id>.zerobus.<region>.azuredatabricks.net`),
`DATABRICKS_CLIENT_ID`, `DATABRICKS_CLIENT_SECRET`, `DATABRICKS_CATALOG`
(your catalog), `DATABRICKS_SCHEMA` (`default`) and
`DATABRICKS_TABLE` (`zerobus_demo_events`).

### 1.6 Test the credentials before going on

```bash
cd zerobus-integration
set -a; source .env; set +a
curl -s -u "$DATABRICKS_CLIENT_ID:$DATABRICKS_CLIENT_SECRET" -d 'grant_type=client_credentials&scope=all-apis' "$DATABRICKS_URL/oidc/v1/token" | python3 -c "import sys,json; d=json.load(sys.stdin); print({k:('<redacted>' if k=='access_token' else v) for k,v in d.items()})"
```

Good: `token_type`, `expires_in`, `scope: all-apis`. `access_denied`
with a scope message: ask the admin for a new secret on the service
principal page. `invalid_client`: mistyped or truncated secret.

## Path A. Local broker + self-managed Micro-Integration

Prerequisites: Docker Desktop, Python 3 with `venv`, `curl`.

### A.1 Start and configure the broker

```bash
cd local-broker
./docker-run.sh
cp .env.example .env
```

Edit `.env`: replace both `CHANGEME_...` passwords (publisher and
consumer). Then create the VPN, queue, dead message queue, client
profile and users:

```bash
./semp/configure-local-broker.sh
```

Check in Broker Manager, http://localhost:8080 (admin/admin), VPN
`zerobus-demo`: queue `q-zerobus-ingest` and `dmq-zerobus-ingest` exist.
The container has `--restart unless-stopped`, so it and its config
survive a laptop or Docker restart (only `docker rm -f` wipes them).

### A.2 Start the Micro-Integration

```bash
cd zerobus-integration
cp application.yml.example application.yml
```

`application.yml` needs no edits. In `.env` (created in 1.5) also set:
`SOLACE_CLIENT_USERNAME` / `SOLACE_CLIENT_PASSWORD` to the **consumer**
user and password from `local-broker/.env` (`CONSUMER_USER`,
`CONSUMER_PASSWORD`) and `SOLACE_CONNECTOR_SECURITY_USERS_0_PASSWORD` to
a password of your choice for the health check. Leave
`SOLACE_SMF_HOST=tcp://host.docker.internal:55554`. Then:

```bash
docker compose up -d
```

### A.3 Health check

```bash
cd zerobus-integration
set -a; . ./.env; set +a
curl -s -u "$SOLACE_CONNECTOR_SECURITY_USERS_0_NAME:$SOLACE_CONNECTOR_SECURITY_USERS_0_PASSWORD" http://localhost:8081/actuator/health
```

Expected `{"status":"UP"...}`. If not, `docker logs zerobus-integration`
and the troubleshooting table in
[`zerobus-integration.md`](zerobus-integration.md).

### A.4 Run the demo

```bash
cd demo-apps
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python publisher.py --dry-run
python publisher.py --count 10 --interval 0.5
```

`publisher.py` reads `PUBLISHER_USER`/`PUBLISHER_PASSWORD` from
`local-broker/.env`. Then query in Databricks:

```sql
SELECT * FROM <catalog>.default.zerobus_demo_events
ORDER BY event_time DESC;
```

New rows appear within seconds:

![Rows in the Delta table](images/21-delta-table-rows.png)

## Path B. Solace Cloud broker + Cloud-Managed Micro-Integration

Everything except creating the API token is scripted, from
`cloud-setup/`. Prerequisites: a Solace Cloud account with the
Micro-Integration Manager role and Micro-Integrations enabled,
`curl`, `jq`, `terraform` (>= 1.5), `openssl`, and the Python
environment from A.4. Part 1 must be done (the Micro-Integration reads
`zerobus-integration/.env`).

### B.1 Create the API token (the one manual step)

Solace Cloud Console, user menu, **Token Management**, **Create Token**,
with permission to read and create services and `micro_integrations:*:*`.
Then:

```bash
cd cloud-setup/solace-cloud-api
cp .env.example .env
```

Put the token in `.env` and set `SOLACE_CLOUD_API_BASE` to the API of the
**Home Cloud of your organization**: `https://api.solace.cloud/api/v2`
(US East), `https://api.solacecloud.eu/api/v2` (EU), and so on. A wrong
region gives `401 Your permissions have changed`. Never commit or paste
the token.

### B.2 Discover and pick a datacenter

```bash
./discover-micro-integration.sh
./lookup-service-options.sh
```

Copy `cloud-setup/terraform/terraform.tfvars.example` to `terraform.tfvars`
and set `datacenter_id` (this demo: `eks-us-east-1a`). The datacenter must
have spare non-broker capacity: on `aks-eastus-second-dc` the
Micro-Integration ended in `error` after ~10 minutes with an empty error
log. The `datacenter_id` can not be changed later (see B.7).

### B.3 Create the broker service

```bash
cd ../terraform
./run-terraform.sh init
./run-terraform.sh plan
./run-terraform.sh apply
```

About 5 minutes.

### B.4 Fetch the connection details and configure the broker

```bash
cd ../solace-cloud-api
./show-service-connection.sh
./get-service-endpoints.sh
./configure-cloud-broker.sh
```

This writes git-ignored files to `output/` (manager credential, endpoints,
generated publisher and consumer passwords, TLS trust store) and creates
the client profile, queue `q-zerobus-ingest`, DMQ `dmq-zerobus-ingest`,
and users `pub-zerobus` and `sub-zerobus`. It can be re-run safely.

### B.5 Create and deploy the Micro-Integration

```bash
./micro-integration.sh create
./micro-integration.sh create-flow
./micro-integration.sh deploy
```

`deploy` polls until the state is `running` (a few minutes). Check any
time with `./micro-integration.sh status`. In the Console under
**Micro-Integrations** it looks like this; the flow is `Running` and
the counters show messages passed:

![Cloud-Managed Micro-Integration running, 5 messages passed](images/20-cloud-mi-running.png)

### B.6 Run the demo

```bash
cd ../../demo-apps
source .venv/bin/activate
python publisher.py --target cloud --count 5
```

Then run the same SQL query as in A.4. In the Console, **Total Messages**
on the Micro-Integration page increases and **Total Errors** stays 0.

If the state is `running` and then goes `down`, open the Console,
Micro-Integrations, your integration, ellipsis, **View Logs**:

![Error logs of a failed run](images/22-cloud-mi-error-logs.png)

That run failed with `Failed to create Zerobus stream for binding
'output-0' / table '<catalog>.default.output-0'`: the flow had no
full table name as destination. `micro-integration.sh` now sets it.

### B.7 Tear down

```bash
cd cloud-setup/solace-cloud-api
./micro-integration.sh undeploy
./micro-integration.sh delete
cd ../terraform
./run-terraform.sh destroy
```

To move to another datacenter: restore the old `datacenter_id` in
`terraform.tfvars`, destroy, set the new value, apply, then repeat B.4 to
B.6. Details and the problems met: [`../cloud-setup/README.md`](../cloud-setup/README.md)
and [`cloud-managed-micro-integration.md`](cloud-managed-micro-integration.md).

## Between demo runs

To start from an empty table and queues, see "Resetting between runs" in
[`demo-apps.md`](demo-apps.md). The live-demo script is in the same file.
