# Provisions the Solace Cloud event broker service(s) for this demo.
#
# Scope: this only provisions the SERVICE(S) themselves (Mission Control
# level, via the solacecloud provider). It does NOT configure anything
# inside the broker (Message VPN details beyond the name, queues, ACL
# profiles, client-usernames) -- that's SEMP-level config, handled
# separately (see ../../local-broker/semp/ for the local-broker side, and
# this folder's README.md for what else may be needed on the cloud-broker
# side).

resource "solacecloud_service" "main" {
  name             = "${var.name_prefix}-service"
  datacenter_id    = var.datacenter_id
  service_class_id = var.service_class_id
  message_vpn_name = var.message_vpn_name
}

# If this demo needs more than one service, duplicate the block above
# with a different resource name (and, if it's in a different Solace
# Cloud org, add `provider = solacecloud.<alias>` -- see provider.tf) and
# give each its own `datacenter_id`/`message_vpn_name` variable.
