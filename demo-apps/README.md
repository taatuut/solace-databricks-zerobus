# Demo apps (data producers)

One publisher, `publisher.py`, publishing synthetic sensor-reading events
to the **local** broker on `<ZEROBUS_TOPIC_SUBSCRIPTION-prefix>/<device_id>/<reading_type>`
(default prefix `zerobus-demo/sensor`, see `../local-broker/.env.example`).

Each event's JSON shape — `device_id`, `reading_type`, `value`, `unit`,
`event_time` — matches `sample-payloads/sensor-reading.json` and is meant
to match the target Delta table's columns one-for-one. If the table
schema changes, update all three together: this script, the sample
payload, and the table DDL (see `../docs/zerobus-integration.md`).

## Usage

```bash
pip install -r requirements.txt
python publisher.py --dry-run           # sanity-check payloads, no broker needed
python publisher.py --count 20 --interval 0.5
python publisher.py --target cloud --count 5   # Solace Cloud broker (TLS)
```

`--target cloud` reads the broker host and generated publisher credentials
from `cloud-setup/output/cloud-broker.env` (created by
`cloud-setup/solace-cloud-api/configure-cloud-broker.sh`) and trusts the
certificates in `cloud-setup/output/trust-store/`.

`--dry-run` prints the payloads it would publish instead of connecting to
a broker — useful for checking the generated data shape before the local
broker or the Micro-Integration is even running.

See [`../docs/demo-apps.md`](../docs/demo-apps.md) for the proposed
live-demo script.
