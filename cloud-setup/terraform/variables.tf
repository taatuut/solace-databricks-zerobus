variable "solace_cloud_api_token" {
  description = "Mission Control API token for this Solace Cloud organization (Mission Control > API Tokens, scope: Create Services + My/Organization Services). NEVER commit the real value -- set it in terraform.tfvars (gitignored) or the TF_VAR_solace_cloud_api_token env var."
  type        = string
  sensitive   = true
}

variable "solace_cloud_api_base_url" {
  description = "Mission Control REST API base URL for this org's Home Cloud. Confirm in the console (My Account/Org settings) -- do not assume it is always https://api.solace.cloud/."
  type        = string
  default     = "https://api.solace.cloud/"
}

variable "datacenter_id" {
  description = "Solace Cloud datacenterId for the service. Look up the exact, CURRENT value via GET {solace_cloud_api_base_url}api/v2/missionControl/datacenters using your token -- these are account/contract-specific and change over time. Watch out for look-alike dedicated/private datacenters that show up alongside the genuine public region for a given provider."
  type        = string
}

variable "service_class_id" {
  description = "Solace Cloud serviceClassId for the service (e.g. \"DEVELOPER\" for the free/dev tier). CONFIRM THE EXACT STRING before relying on a default -- run `terraform plan` and read any validation error, or check GET {solace_cloud_api_base_url}api/v2/missionControl/serviceClasses with your token."
  type        = string
  default     = "DEVELOPER"
}

variable "message_vpn_name" {
  description = "Message VPN name to set EXPLICITLY on the service, instead of letting Solace Cloud auto-generate/truncate one from the service name."
  type        = string
}

variable "name_prefix" {
  description = "Prefix for the service name."
  type        = string
}
