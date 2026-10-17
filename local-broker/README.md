# Local broker

A single-availability, self-managed Solace PubSub+ broker that receives
all demo traffic from `demo-apps/publisher.py` and holds it on a queue
(with a Dead Message Queue) that the Zerobus Micro-Integration reads
from. See `../docs/topology.md` for the full data flow.

## Usage

```bash
./docker-run.sh
cp .env.example .env   # fill in real values
./semp/configure-local-broker.sh
```
