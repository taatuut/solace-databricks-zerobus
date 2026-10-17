# Output the whole resource object, marked sensitive (it's expected to
# carry generated SMF/REST host:port and management credentials). Inspect
# the real structure after apply with:
#   terraform output -json service | jq .
# See this folder's README.md, "After terraform apply", for how to map
# whatever comes out of that onto local-broker/.env or other local config.

output "service" {
  value     = solacecloud_service.main
  sensitive = true
}
