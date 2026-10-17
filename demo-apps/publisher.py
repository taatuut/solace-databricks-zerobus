#!/usr/bin/env python3
"""Publishes sample sensor-reading events to the local Solace broker, on
the topic the Zerobus ingest queue subscribes to (see
../local-broker/.env.example, ZEROBUS_TOPIC_SUBSCRIPTION).

Each event's JSON shape matches demo-apps/sample-payloads/sensor-reading.json
and the target Delta table's expected columns (see
../docs/zerobus-integration.md) -- device_id, reading_type, value, unit,
event_time. Keep these three in sync if the schema changes: this script,
the sample payload, and the Delta table DDL.

Note on event_time: the Zerobus JSON ingest path rejects an ISO-8601 text
value for a TIMESTAMP column ("invalid digit found in string"), so
event_time is sent as an integer, microseconds since the Unix epoch.

Targets: --target local (default) publishes to the local Docker broker;
--target cloud publishes to the Solace Cloud broker created by
../cloud-setup/, over TLS, using the connection details and generated
publisher credentials in ../output/cloud-broker.env and the trust store
in ../output/trust-store/ (both written by
../cloud-setup/solace-cloud-api/configure-cloud-broker.sh).

Usage:
  python publisher.py                  # publish 10 events, 1s apart
  python publisher.py --target cloud   # same, to the Solace Cloud broker
  python publisher.py --count 50 --interval 0.2
  python publisher.py --dry-run        # build and print payloads, no broker needed

Requires: ../local-broker/.env populated (LOCAL_SMF_HOST, LOCAL_MSG_VPN,
PUBLISHER_USER, PUBLISHER_PASSWORD) -- see ../local-broker/.env.example.
"""
import argparse
import json
import os
import random
import time
from datetime import datetime, timezone
from pathlib import Path

from dotenv import dotenv_values, load_dotenv

ENV_FILE = Path(__file__).resolve().parent.parent / "local-broker" / ".env"
load_dotenv(ENV_FILE)

REPO_ROOT = Path(__file__).resolve().parent.parent
CLOUD_ENV_FILE = REPO_ROOT / "output" / "cloud-broker.env"
CLOUD_TRUST_STORE = REPO_ROOT / "output" / "trust-store"

TOPIC_PREFIX = os.environ.get("ZEROBUS_TOPIC_SUBSCRIPTION", "zerobus-demo/sensor/>").rstrip("/>")
READING_TYPES = [
    ("temperature", "celsius", 15.0, 28.0),
    ("humidity", "percent", 30.0, 70.0),
    ("pressure", "hpa", 990.0, 1030.0),
]
DEVICE_IDS = [f"sensor-{i:04d}" for i in (12, 42, 77, 103, 256)]


def build_event() -> dict:
    reading_type, unit, lo, hi = random.choice(READING_TYPES)
    return {
        "device_id": random.choice(DEVICE_IDS),
        "reading_type": reading_type,
        "value": round(random.uniform(lo, hi), 1),
        "unit": unit,
        "event_time": int(datetime.now(timezone.utc).timestamp() * 1_000_000),
    }


def connection_settings(target: str):
    """Returns (service properties, TLS strategy or None) for the target."""
    if target == "cloud":
        if not CLOUD_ENV_FILE.exists():
            raise SystemExit(f"Missing {CLOUD_ENV_FILE}: run cloud-setup/solace-cloud-api/configure-cloud-broker.sh first.")
        if not any(CLOUD_TRUST_STORE.glob("*.pem")):
            raise SystemExit(f"No trust store in {CLOUD_TRUST_STORE}: rerun configure-cloud-broker.sh (it downloads the CA certificate).")
        cfg = dotenv_values(CLOUD_ENV_FILE)
        from solace.messaging.config.transport_security_strategy import TLS

        tls = TLS.create().with_certificate_validation(
            ignore_expiration=False, validate_server_name=True, trust_store_file_path=str(CLOUD_TRUST_STORE)
        )
        return (
            {
                "solace.messaging.transport.host": cfg["CLOUD_SMF_HOST"],
                "solace.messaging.service.vpn-name": cfg["CLOUD_MSG_VPN"],
                "solace.messaging.authentication.scheme.basic.username": cfg["CLOUD_PUBLISHER_USER"],
                "solace.messaging.authentication.scheme.basic.password": cfg["CLOUD_PUBLISHER_PASSWORD"],
            },
            tls,
        )
    return (
        {
            "solace.messaging.transport.host": f"tcp://{os.environ['LOCAL_SMF_HOST']}",
            "solace.messaging.service.vpn-name": os.environ["LOCAL_MSG_VPN"],
            "solace.messaging.authentication.scheme.basic.username": os.environ["PUBLISHER_USER"],
            "solace.messaging.authentication.scheme.basic.password": os.environ["PUBLISHER_PASSWORD"],
        },
        None,
    )


def publish(count: int, interval: float, dry_run: bool, target: str = "local") -> None:
    if dry_run:
        for _ in range(count):
            event = build_event()
            topic = f"{TOPIC_PREFIX}/{event['device_id']}/{event['reading_type']}"
            print(f"[dry-run] {topic} -> {json.dumps(event)}")
            time.sleep(interval)
        return

    # Imported lazily so --dry-run works without the Solace Python API
    # installed/a broker reachable.
    from solace.messaging.messaging_service import MessagingService
    from solace.messaging.resources.topic import Topic

    properties, tls = connection_settings(target)
    builder = MessagingService.builder().from_properties(properties)
    if tls is not None:
        builder = builder.with_transport_security_strategy(tls)
    messaging_service = builder.build()
    print(f"Connecting to the {target} broker at {properties['solace.messaging.transport.host']} ...")
    messaging_service.connect()
    publisher = messaging_service.create_direct_message_publisher_builder().build()
    publisher.start()

    try:
        for _ in range(count):
            event = build_event()
            topic = f"{TOPIC_PREFIX}/{event['device_id']}/{event['reading_type']}"
            message = messaging_service.message_builder().build(json.dumps(event))
            publisher.publish(destination=Topic.of(topic), message=message)
            print(f"{topic} -> {json.dumps(event)}")
            time.sleep(interval)
    finally:
        publisher.terminate()
        messaging_service.disconnect()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--count", type=int, default=10, help="number of events to publish (default: 10)")
    parser.add_argument("--interval", type=float, default=1.0, help="seconds between events (default: 1.0)")
    parser.add_argument("--target", choices=["local", "cloud"], default="local", help="broker to publish to (default: local)")
    parser.add_argument("--dry-run", action="store_true", help="print payloads instead of publishing to a broker")
    args = parser.parse_args()
    publish(args.count, args.interval, args.dry_run, args.target)

