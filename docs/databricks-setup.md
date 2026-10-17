# Databricks setup (Azure)

Console walk-through for preparing the Databricks side of the demo. It
covers the workspace checks, a SQL warehouse, and the target schema.
Placeholders: `<catalog>` is an existing Unity Catalog catalog you can
create schemas in, `<schema>` is the schema for the demo table (this demo
uses `zerobus_demo`).

> The screenshots in `docs/images/` show real workspace, subscription and
> user identifiers, so that folder is git-ignored and exists only in the
> local checkout of the author. On a fresh clone the image links below
> are broken by design; the text stands on its own.

Permissions overview (who needs what): see section 1.1 of
[`runbook.md`](runbook.md).

See [`zerobus-integration.md`](zerobus-integration.md) for the full list
of Databricks-side prerequisites and the table DDL.

## 1. Confirm the workspace meets the Zerobus requirements

1. **Unity Catalog enabled.** In the workspace open **Catalog**. Unity
   Catalog catalogs (plus `system` and the `samples` share) must be
   listed next to the legacy `hive_metastore`.

   ![Catalog explorer](images/01-catalog-unity-catalog.png)

2. **Premium tier and region.** In the Azure portal open **Azure
   Databricks**, then the workspace. On **Overview** the **Pricing Tier**
   must be **Premium**, and **Location** must be a Zerobus-supported
   region (check the *Ingestion* table in the
   [feature region support](https://learn.microsoft.com/en-us/azure/databricks/resources/feature-region-support#ingestion)
   page; East US is listed as supported). The target table must be in
   the same region as the workspace.

   ![Azure Databricks workspaces](images/02-azure-databricks-workspaces.png)
   ![Workspace overview with Premium tier](images/03-azure-overview-premium.png)

3. **No compliance security profile.** In the workspace resource open
   **Settings > Security & compliance**. **Enable compliance security
   profile** must be unchecked (it cannot be disabled once enabled, and
   such workspaces are not supported).

   ![Security and compliance settings](images/04-azure-security-compliance.png)

## 2. Create a SQL warehouse

SQL statements (schema, table, grants) need compute. A new workspace may
have none.

1. In the workspace open **SQL Warehouses** and click **Create SQL
   warehouse**.

   ![No SQL warehouses yet](images/05-sql-warehouses-empty.png)

2. Name `zerobus-demo`, cluster size **2X-Small**, auto stop after **10**
   minutes, scaling min 1 / max 1, type **Serverless**. Click **Create**.

   ![New SQL warehouse dialog](images/06-new-sql-warehouse-dialog.png)

3. Wait until the status is **Running**.

   ![SQL warehouse running](images/07-sql-warehouse-running.png)

## 3. Create the schema

1. Open **SQL Editor** and click **SQL Query**.

   ![SQL Editor, new query](images/08-sql-editor-new-query.png)

2. In the compute dropdown at the top right select `zerobus-demo`, and
   check that the catalog selector shows `<catalog>`.

   ![Connect the query to the warehouse](images/09-sql-editor-connect-warehouse.png)

3. Run:

   ```sql
   CREATE SCHEMA IF NOT EXISTS <catalog>.<schema>;
   ```

   ![Create schema statement](images/10-sql-editor-create-schema.png)

   Requires `USE CATALOG` and `CREATE SCHEMA` on `<catalog>`. Without
   them the statement fails:

   ![Permission denied on CREATE SCHEMA](images/11-create-schema-permission-denied.png)

## 4. If you lack permissions to create a schema or catalog

Check who owns the catalogs:

```sql
SELECT catalog_name, catalog_owner FROM system.information_schema.catalogs;
```

![Catalog owners](images/12-catalog-owners.png)

A catalog owned by someone else (or by the workspace admins group) means
you need an owner or admin to grant `USE CATALOG` and `CREATE SCHEMA`
on it, or to point you to an existing schema where you hold `USE SCHEMA`
and `CREATE TABLE`.

Creating a catalog of your own is not an alternative without the
`CREATE CATALOG` privilege on the metastore:

- `CREATE CATALOG <name>;` fails with *Metastore storage root URL does
  not exist* (the metastore has no root storage, only Default Storage
  through the UI).

  ![CREATE CATALOG storage error](images/13-create-catalog-storage-error.png)

- The **Create a catalog** entry is missing from the **+** menu and the
  **Create** menu in **Catalog** (the UI hides it without the privilege).

  ![Catalog + menu](images/14-catalog-plus-menu.png)
  ![Catalog Create menu](images/15-catalog-create-menu.png)

Creating the service principal also typically needs admin rights; ask
for it (or for the service principal manager role) in the same request.

## 5. Find a schema you can already write to

Privileges that come through a group do not show up in
`information_schema`, so the reliable test is to create the table (next
section) in an existing schema such as `<catalog>.default`. To list direct
grants and owned tables:

```sql
SELECT 'table' AS scope, table_catalog AS catalog_name, table_schema AS schema_name, table_name AS object_name, privilege_type
FROM system.information_schema.table_privileges
WHERE grantee = current_user()
UNION ALL
SELECT 'schema', catalog_name, schema_name, NULL, privilege_type
FROM system.information_schema.schema_privileges
WHERE grantee = current_user()
UNION ALL
SELECT 'owner', table_catalog, table_schema, table_name, 'OWNER'
FROM system.information_schema.tables
WHERE table_owner = current_user();
```

![No direct grants](images/16-existing-privileges-none.png)

The `samples` catalog (a Delta Sharing share, read-only) and
`hive_metastore` (legacy, not supported by Zerobus) cannot be used as a
target.

## 6. Create the target table

```sql
CREATE TABLE <catalog>.<schema>.zerobus_demo_events (
  device_id     STRING,
  reading_type  STRING,
  value         DOUBLE,
  unit          STRING,
  event_time    TIMESTAMP
);
```

![Create table](images/17-create-table-ok.png)

Verify it is a Unity Catalog managed Delta table:

```sql
DESCRIBE TABLE EXTENDED <catalog>.<schema>.zerobus_demo_events;
```

`Type` must be `MANAGED` and `Provider` must be `delta`.

![Describe table](images/18-describe-table-managed-delta.png)

## 7. Service principal and OAuth secret (needs a workspace admin)

Creating a service principal and its OAuth secret requires workspace
admin rights. The *service principal manager* role is not enough to
create a secret. If **Settings** shows only the **User** section (no
**Workspace admin > Identity and access**), ask an admin to do this:

1. Create a Databricks-managed service principal (not an Entra one), for
   example `databricks-zerobus-service-principal`.
2. On the service principal's own page, open the **Secrets** tab and
   generate an OAuth secret with a limited lifetime. The demo secret is
   valid for 90 days (see "Secret lifetime and rotation" below). The
   secret is shown only once.
3. Send the **application (client) ID** and the **secret** through a
   private channel where the message can be deleted afterwards, and store
   them in a password manager. Never paste the secret into a chat, a
   ticket or a file in the repository.

![User settings without admin section](images/19-user-settings-no-admin.png)

**Pitfall met on 16/10/2026:** the first secret was refused by Databricks
with `Scopes 'all-apis' are not assigned to the client`, even though the
grants were correct. The admin issued a new secret directly on the
service principal page, and that one worked. See section 9 to test a
secret before putting it into the integration.

## 8. Grant the service principal access

The service principal needs these privileges, in this form (the
`<application-id>` is the client ID from section 7). Privileges on the
table are granted by the table owner, privileges on the catalog and
schema by their owner or someone with `MANAGE`:

```sql
GRANT USE CATALOG ON CATALOG <catalog> TO `<application-id>`;
GRANT USE SCHEMA ON SCHEMA <catalog>.<schema> TO `<application-id>`;
GRANT MODIFY, SELECT ON TABLE <catalog>.<schema>.zerobus_demo_events TO `<application-id>`;
```

`MODIFY` and `SELECT` must both be granted explicitly on the table, even
if the principal could inherit them from a higher level.

If you are not an owner (the common case in a shared workspace), the
`GRANT` statements fail with `PERMISSION_DENIED: User does not have
MANAGE on ...`. Ask the catalog owner or an admin to run the first two,
and run the third yourself if you own the table.

### Check what was granted

On the table (works for the table owner):

```sql
SHOW GRANTS ON TABLE <catalog>.<schema>.zerobus_demo_events;
```

You should see `MODIFY` and `SELECT` for the application ID. For the
catalog and schema, `SHOW GRANTS` needs `READ METADATA` or `MANAGE`, which
a normal user usually lacks. Use **Catalog > (catalog or schema) >
Permissions** in the UI instead and look for the principal with
`USE CATALOG` and `USE SCHEMA`. Privileges that come through a group do
not show up in `information_schema`.

### Least privilege

These are the only privileges the pipeline needs (as in the `GRANT`
statements above):

| Level | Privilege | Why |
| --- | --- | --- |
| Catalog | `USE CATALOG` | resolve the catalog |
| Schema | `USE SCHEMA` | resolve the schema |
| Table | `MODIFY` and `SELECT` | Zerobus writes rows to the table |

Nothing else is required: not `MANAGE`, not `CREATE TABLE`, not
`READ METADATA`, and no privileges on other tables.

State on 16/10/2026 for this demo: the service principal has `USE
CATALOG` on `<catalog>`, `USE SCHEMA`, `MANAGE` and `READ
METADATA` on `<catalog>.default`, and `MODIFY` and `SELECT` on
the table. The demo works with this. The extra `MANAGE` and `READ
METADATA` on the schema are not needed and were deliberately left in
place for the demo; remove them in any setup beyond a demo.

### Secret lifetime and rotation

The OAuth secret is valid for 90 days. Before it expires, an admin
issues a new secret on the service principal's page. Then replace
`DATABRICKS_CLIENT_SECRET` in `zerobus-integration/.env`, test it with
section 9, and recreate the container so it picks up the new value
(`docker compose up -d --force-recreate`, in `zerobus-integration`).
After the demo, add a calendar reminder a week before the expiry date.

## 9. Test the client ID and secret before using them

Request a token directly, so a problem with the credentials is separated
from a problem in the Micro-Integration. This reads the values from
`zerobus-integration/.env` and prints neither the secret nor the token:

```
cd zerobus-integration
set -a; source .env; set +a
curl -s -u "$DATABRICKS_CLIENT_ID:$DATABRICKS_CLIENT_SECRET" -d 'grant_type=client_credentials&scope=all-apis' "$DATABRICKS_URL/oidc/v1/token" | python3 -c "import sys,json; d=json.load(sys.stdin); print({k:('<redacted>' if k=='access_token' else v) for k,v in d.items()})"
```

A good result contains `token_type`, `expires_in` and `scope: all-apis`.
`access_denied` with a scope message means the client lacks the scope
(ask the admin for a new secret on the service principal page).
`invalid_client` usually means a mistyped or truncated secret.

## 10. Where the values go

The values from this guide end up in `zerobus-integration/.env`
(git-ignored), as described in
[`zerobus-integration.md`](zerobus-integration.md): the workspace URL
(`DATABRICKS_URL`), the Zerobus endpoint (`DATABRICKS_SERVER_ENDPOINT`,
for Azure `https://<workspace-id>.zerobus.<region>.azuredatabricks.net`),
the client ID and secret, and the catalog, schema and table names.
