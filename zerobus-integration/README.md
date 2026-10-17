# Zerobus Micro-Integration

Runs the **Solace Micro-Integration for Databricks Zerobus**
(self-managed, Docker image `solace/solace-micro-integration-databricks-
zerobus`) that reads from the local broker's ingest queue and writes
records into the target Databricks Delta table.

See [`../docs/zerobus-integration.md`](../docs/zerobus-integration.md)
for the full prerequisite checklist and what every configuration property
means before filling in `application.yml`.

## Usage

```bash
cp application.yml.example application.yml
cp .env.example .env
docker compose up
```

`application.yml` needs no edits: it reads every value from `.env`. Fill in
`.env` (git-ignored) first.

Then check the health/Actuator endpoint (see `docker-compose.yml` for the
exposed port) before publishing any demo events.

## Why `application.yml` AND `.env`

The Micro-Integration is configured via a single Spring Boot
`application.yml`. To avoid ever committing real secrets in that file,
reference them as `${DATABRICKS_CLIENT_SECRET}`-style placeholders in
`application.yml` and supply the actual values via `.env` /
`docker-compose.yml`'s `env_file`, the same way the rest of this repo
keeps secrets out of committed files (see `../docs/notes-and-gotchas.md`, "Secrets").

## Pinning the image

Docker Hub offers only the `latest` tag, so a plain `docker compose up`
can pick up a newer image later. To keep runs reproducible, pin the image
you have tested by its digest. Run this once, after the first successful
`docker compose up`; it adds the pin to your git-ignored `.env`:

```bash
cd zerobus-integration
echo "ZEROBUS_MI_IMAGE=$(docker image inspect solace/solace-micro-integration-databricks-zerobus:latest --format '{{index .RepoDigests 0}}')" >> .env
docker compose config | grep image
```

The last command should print the `@sha256:...` reference. To go back to
`latest`, delete the `ZEROBUS_MI_IMAGE` line from `.env`.
