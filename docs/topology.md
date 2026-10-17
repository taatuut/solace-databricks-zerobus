# Topology

## Overview

```
demo-apps/publisher.py
   --publishes JSON events-->
local Solace broker
   (Message VPN, queue "q-zerobus-ingest" with a DMQ)
   --Micro-Integration consumes the queue-->
Solace Micro-Integration for Databricks Zerobus
   (self-managed, Docker, Spring Cloud Stream binder "dbzerobus")
   --gRPC, OAuth2 client-credentials-->
Databricks Zerobus
   --writes rows into-->
Unity Catalog managed Delta table
```

One broker, one downstream system — no bridges, no REST Delivery Points,
no multi-cloud routing. If a platform (Solace Cloud) broker is added
later instead of/alongside the local one, update this diagram rather than leaving this description stale.

## Brokers

- **Local broker** (`local-broker/`): a single-availability, self-managed
  Solace PubSub+ software broker running in Docker. Default and only
  broker needed for this demo.
- **Platform broker** (`cloud-setup/`): a Solace Cloud service with the
  Cloud-Managed Micro-Integration for Databricks Zerobus, in parallel to
  the local path. Created by script, see `cloud-setup/README.md`.

## Topic taxonomy

The publisher sends to `zerobus-demo/sensor/<device_id>/<reading_type>`;
the ingest queue subscribes to `zerobus-demo/sensor/>`. The payload shape
is in `demo-apps/sample-payloads/sensor-reading.json`.

## Why a Micro-Integration, and not a custom consumer?

The Solace Micro-Integration for Databricks Zerobus is a ready-made,
Solace-supported bridge purpose-built for this exact path (Solace queue
-> Databricks Delta table): it handles OAuth token refresh, schema
validation against the live Delta table, retriable-error stream recovery
with backoff, and DMQ routing for non-retriable errors, so the demo
doesn't need a custom consumer application just to move bytes from Solace
into Databricks. The trade-off: it's currently a Beta connector, so
behavior/config details should be re-checked against Solace's docs (see
[`notes-and-gotchas.md`](notes-and-gotchas.md)) rather than assumed
stable long-term.
