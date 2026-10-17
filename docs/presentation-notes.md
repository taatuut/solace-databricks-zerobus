# Presentation notes -- explicitly call these out in the talk itself

## 1. This is a direct write path, not a staged/batched one

Worth making explicit: Zerobus writes records into the Delta table via a
gRPC call per batch of events, acknowledged by Solace only once Databricks
confirms durability — there's no intermediate file landing, no
Kafka/Auto Loader hop, and no fixed batch-job cadence to wait out. That's
the actual point of the demo, so say it plainly rather than letting the
audience assume a more conventional ETL path is happening underneath.

## 2. Delivery is at-least-once, not exactly-once

If the demo re-publishes a message (e.g. after a connectivity hiccup), a
duplicate row can land in the table — there's no built-in deduplication.
Don't claim exactly-once semantics unless a dedup strategy has actually
been added downstream.

## 3. This is a Beta connector

Worth a one-line caveat in the talk: the Micro-Integration for Databricks
Zerobus is Beta at the time this demo was built — configuration details
and supported regions may change. Say so rather than presenting it as a
long-GA, stable integration.
