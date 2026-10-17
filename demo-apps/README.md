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
cd demo-apps
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python publisher.py --dry-run
python publisher.py --count 20 --interval 0.5
python publisher.py --target cloud --count 5
```

Run these from the `demo-apps/` folder. `--dry-run` prints the payloads it
would publish instead of connecting to a broker, which is useful for
checking the data shape before any broker or Micro-Integration is running.

`--target cloud` publishes to the Solace Cloud broker over TLS. It reads
the broker host and the generated publisher credentials from
`output/cloud-broker.env` in the repository root (created by
`cloud-setup/solace-cloud-api/configure-cloud-broker.sh`) and trusts the
certificates in `output/trust-store/`.

See [`../docs/demo-apps.md`](../docs/demo-apps.md) for the proposed
live-demo script.
