# Terraform: platform broker service(s)

Provisions the Solace Cloud service(s) for this demo repeatably. See
`main.tf` for what it actually creates.

## First time

Edit `terraform.tfvars` after copying it: datacenter, service class, VPN
name and name prefix (no secrets in this file). Skip `undeploy` below if
the Micro-Integration is not running.

```bash
cd cloud-setup/terraform
cp terraform.tfvars.example terraform.tfvars
./run-terraform.sh init
./run-terraform.sh plan
./run-terraform.sh apply
```

`run-terraform.sh` takes the Solace Cloud API token and base URL from
`../solace-cloud-api/.env` and passes them to Terraform as `TF_VAR_*`, so
the token is never written to `terraform.tfvars`. Look up the datacenter
with `../solace-cloud-api/lookup-service-options.sh`.

## Changing the datacenter

`datacenter_id` can not be changed on an existing service ("Immutable
Attribute Change"), and `destroy` runs the same check. To move a service:
set the old value back in `terraform.tfvars`, run `./run-terraform.sh
destroy`, set the new value, run `./run-terraform.sh apply`, then repeat
the scripts from step 4 of `../README.md`. Delete a Micro-Integration
(`../solace-cloud-api/micro-integration.sh delete`) before destroying its
service.

## After `terraform apply`

1. Read the connection details with redaction:
   `../solace-cloud-api/show-service-connection.sh`.
2. Fetch the connection endpoints (SMF/SEMP/REST TLS ports and host):
   `../solace-cloud-api/get-service-endpoints.sh`.
3. Configure the broker (queue, DMQ, users, ACLs, trust store) with
   `../solace-cloud-api/configure-cloud-broker.sh`. It uses the SEMP v2
   Config API with the manager credential from `output/service.json`.
4. Create and deploy the Micro-Integration with
   `../solace-cloud-api/micro-integration.sh create|create-flow|deploy`.

See `../README.md` for the full ordered procedure.

## Removing the service(s)

Delete the Micro-Integration first (it is not managed by Terraform):

```bash
cd cloud-setup/solace-cloud-api
./micro-integration.sh undeploy
./micro-integration.sh delete
cd ../terraform
./run-terraform.sh destroy
```

Caveat: `datacenter_id` is immutable in the provider. If `terraform.tfvars`
differs from the state, even `destroy` fails. Restore the old value first,
destroy, then set the new value and apply (see "Changing the datacenter").
