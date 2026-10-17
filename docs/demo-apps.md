# Demo apps: explanation and script

First-time setup of everything: [`runbook.md`](runbook.md).

## Proposed script (matching the presentation/workshop)

All commands run from the repository root unless a `cd` says otherwise.
Before starting: both containers are up (`docker ps` shows
`zerobus-demo-local-broker` and `zerobus-integration`) and the health
check below returns `UP`.

1. Show the empty (or near-empty) target Delta table in Databricks SQL
   (warehouse `zerobus-demo`):

   ```sql
   SELECT * FROM <catalog>.default.zerobus_demo_events
   ORDER BY event_time DESC LIMIT 20;
   ```

2. Start the publisher, publishing a handful of sample events:

   ```
   cd demo-apps
   source .venv/bin/activate
   python publisher.py --count 10 --interval 0.5
   ```

3. Re-run the Databricks SQL query: new rows appear, with the latency
   visibly low (seconds, not a batch-job cadence).
4. Optionally show the Micro-Integration's Actuator health endpoint and
   the Solace broker's queue depth returning to zero (Broker Manager at
   http://localhost:8080, VPN `zerobus-demo`, queue `q-zerobus-ingest`),
   to make the "nothing is being batched/staged" point concrete.

## Health check

The Actuator endpoint listens on container port 8090, published on host
port 8081, and requires HTTP basic auth. The user is defined in
`zerobus-integration/.env` (`SOLACE_CONNECTOR_SECURITY_USERS_0_NAME` and
`..._PASSWORD`). This reads them without printing the password:

```
cd zerobus-integration
set -a; . ./.env; set +a
curl -s -u "$SOLACE_CONNECTOR_SECURITY_USERS_0_NAME:$SOLACE_CONNECTOR_SECURITY_USERS_0_PASSWORD" http://localhost:8081/actuator/health
```

Expected: `{"status":"UP"}` (possibly with more detail). Without `-u` the
endpoint returns 401, and `curl -s` hides that: add `-i` to see the
HTTP status.

## `event_time` format

The target column is `TIMESTAMP`, and the Zerobus JSON ingest path
rejects ISO-8601 text for it (error 4044, "invalid digit found in
string"; the events end up in the dead message queue). The publisher
therefore sends `event_time` as a number: microseconds since the Unix
epoch, e.g. `1791979200000000`. Anything else that publishes to the
queue must do the same. This was inferred from the error message, not
confirmed in the Databricks documentation.

## Cloud variant

The same demo runs against the Solace Cloud broker with the Cloud-Managed
Micro-Integration: `python demo-apps/publisher.py --target cloud --count 5`.
The health check is the MI state (`cloud-setup/solace-cloud-api/micro-integration.sh status`, expect `running`) instead of the Actuator endpoint.

## Timing

Keep the publisher's event count/interval low enough that the Databricks
SQL re-query in step 3 shows a clear, small set of new rows, not a wall of
output — see `demo-apps/README.md` for the relevant flags once the
publisher script exists.

## Resetting between runs

Do this before a demo to start from a clean state. The test data from
the 16/10/2026 bring-up is deliberately left in place as proof that the
setup works; clear it only when you need an empty table.

Empty the Delta table. In the Databricks SQL Editor, with the
`zerobus-demo` warehouse selected:

```sql
DELETE FROM <catalog>.default.zerobus_demo_events;
```

```sql
SELECT COUNT(*) FROM <catalog>.default.zerobus_demo_events;
```

The count should be 0. `DELETE` keeps the table definition and grants,
so the service principal needs no changes.

Empty the dead message queue. Failed events (after 3 redeliveries) wait
in `dmq-zerobus-ingest`:

1. Open Broker Manager at http://localhost:8080 (admin/admin).
2. Open the VPN `zerobus-demo`, then Queues, then `dmq-zerobus-ingest`.
3. Open the Messages Queued tab, select all messages and choose Delete.
4. The tab should show 0 messages queued.

Also check `q-zerobus-ingest` is at 0 messages queued, so no leftovers
are delivered during the demo.

## Fallback

No fallback material exists yet. A short screen recording of steps 1-3
above is the minimum.
